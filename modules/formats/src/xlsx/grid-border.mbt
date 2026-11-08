///|
let cell_border_styles : Array[String] = [
  "none", "thin", "medium", "thick", "double", "hair", "dotted", "dashed", "dashDot",
  "dashDotDot", "mediumDashed", "mediumDashDot", "mediumDashDotDot", "slantDashDot",
]

///|
fn CellBorder::width(self : CellBorder) -> Double {
  match self.style {
    "thin" | "hair" | "dotted" | "dashed" | "dashDot" | "dashDotDot" => 0.75
    "medium"
    | "mediumDashed"
    | "mediumDashDot"
    | "mediumDashDotDot"
    | "slantDashDot" => 1.5
    "thick" | "double" => 2.25
    _ => 0.0
  }
}

///|
fn CellBorder::dash(self : CellBorder) -> Array[Double] {
  let pixels = match self.style {
    "hair" => [1.0, 1.0]
    "dotted" => [2.0, 2.0]
    "dashed" => [3.0, 1.0]
    "mediumDashed" => [9.0, 3.0]
    "dashDot" | "mediumDashDot" | "slantDashDot" => [3.0, 3.0, 9.0, 3.0]
    "dashDotDot" | "mediumDashDotDot" => [3.0, 3.0, 3.0, 3.0, 9.0, 3.0]
    _ => []
  }
  pixels.map(value => value * 0.75)
}

///|
fn CellBorder::paint(
  self : CellBorder,
  rect : @layout.Border,
  strokes : Array[@layout.PositionedPrimitive],
) -> Unit {
  if self.width() == 0 {
    return
  }
  let double = self.style == "double"
  for offset in (if double { [-0.75, 0.75] } else { [0.0] }) {
    let x = rect.x + (if rect.width == 0 { offset } else { 0.0 })
    let y = rect.y + (if rect.width != 0 { offset } else { 0.0 })
    // A cell edge is an open line with butt caps, including each half of a double edge.
    strokes.push(
      Path(
        [@layout.PathSegment::Move(x, y), Line(x + rect.width, y + rect.height)],
        "",
        self.color,
        if double {
          0.75
        } else {
          self.width()
        },
        {
          evenOdd: false,
          fillAlpha: 1,
          strokeAlpha: 1,
          dash: self.dash(),
          cap: 0,
          join: 0,
          miter: 10,
        },
      ),
    )
  }
}

///|
fn visible_neighbor(
  indices : Array[Int32],
  value : Int32,
  after : Bool,
) -> Int32? {
  for low = 0, high = indices.length(); low < high; {
    let middle = low + (high - low) / 2
    if indices[middle] < value || (after && indices[middle] == value) {
      continue middle + 1, high
    } else {
      continue low, middle
    }
  } nobreak {
    indices.get(if after { low } else { low - 1 })
  }
}

///|
fn CellBorder::strength(self : CellBorder) -> Int32 {
  match self.style {
    "double" => 4
    _ => (self.width() / 0.75).to_int()
  }
}

///|
fn Sheet::border_pieces(
  self : Sheet,
  range : Range,
  rect : @layout.Border,
  side : Int32,
  rows : Array[Int32],
  columns : Array[Int32],
  dimensions : Dimensions,
  printing : Bool,
  work : FormulaWork,
) -> Array[(Range, @layout.Border)] raise @failure.Failure {
  let horizontal = side >= 2
  let (first, last) = if horizontal {
    (range.left, range.right)
  } else {
    (range.top, range.bottom)
  }
  if first == last {
    return [(range, rect)]
  }
  let (parallel, across, axis, other_axis) = if horizontal {
    (columns, rows, dimensions.columns, dimensions.rows)
  } else {
    (rows, columns, dimensions.rows, dimensions.columns)
  }
  let after = if horizontal { side == 3 } else { (side == 1) != self.view.rtl }
  let boundary = if horizontal {
    if after {
      range.bottom
    } else {
      range.top
    }
  } else if after {
    range.right
  } else {
    range.left
  }
  let neighbor = visible_neighbor(across, boundary, after)
  let neighbor = if printing && neighbor is None {
    other_axis.neighbor(boundary, after)
  } else {
    neighbor
  }
  guard neighbor is Some(neighbor) else { return [(range, rect)] }
  let pieces : Array[(Range, @layout.Border)] = []
  let mut cursor = visible_neighbor(parallel, first - 1, true)
  while cursor is Some(start) && start <= last {
    work.spend()
    let other = self.cell_range(
      if horizontal {
        { row: neighbor, column: start, }
      } else {
        { row: start, column: neighbor, }
      },
    )
    let end = last.min(if horizontal { other.right } else { other.bottom })
    let size = axis.position(end + 1) - axis.position(start)
    let offset = if horizontal && self.view.rtl {
      axis.position(last + 1) - axis.position(end + 1)
    } else {
      axis.position(start) - axis.position(first)
    }
    pieces.push(
      if horizontal {
        (
          { ..range, left: start, right: end, },
          { ..rect, x: rect.x + offset, width: size, },
        )
      } else {
        (
          { ..range, top: start, bottom: end, },
          { ..rect, y: rect.y + offset, height: size, },
        )
      },
    )
    cursor = visible_neighbor(parallel, end, true)
  }
  pieces
}

///|
// Resolve shared edges once, including hidden axes and derived table borders.
fn Session::border_line(
  self : Session,
  style : CellStyle,
  address : Address,
  range : Range,
  rect : @layout.Border,
  side : Int32,
  rows : Array[Int32],
  columns : Array[Int32],
  conditional : ConditionalRules,
  index : Int32,
  work : FormulaWork,
  dimensions : Dimensions,
  printing : Bool,
) -> (CellBorder, @layout.Border)? raise @failure.Failure {
  let sheet = self.sheets[index]
  let after = if side <= 1 { (side == 1) != sheet.view.rtl } else { side == 3 }
  let boundary = if side <= 1 {
    if after {
      range.right
    } else {
      range.left
    }
  } else if after {
    range.bottom
  } else {
    range.top
  }
  let neighbor = visible_neighbor(
    if side <= 1 {
      columns
    } else {
      rows
    },
    boundary,
    after,
  )
  let inside = neighbor is Some(_)
  if style.borders[side].style == "none" && (inside || !printing) {
    return None
  }
  // Printed cuts retain a winning border owned by the adjacent, unprinted cell.
  let neighbor = match neighbor {
    Some(_) => neighbor
    None =>
      if printing {
        (if side <= 1 { dimensions.columns } else { dimensions.rows }).neighbor(
          boundary, after,
        )
      } else {
        None
      }
  }
  let neighbor = neighbor.map(value => {
    if side <= 1 {
      { ..address, column: value, }
    } else {
      { ..address, row: value, }
    }
  })
  let other = if neighbor is Some(next) {
    let neighbor_range = sheet.cell_range(next)
    let next = Address::{
      row: neighbor_range.top,
      column: neighbor_range.left,
    }
    Some(
      (
        next,
        conditional.applied(
          self.merged_style(sheet, neighbor_range),
          next,
          self.sheets,
          index,
          self.calculation
          .map(calculation => calculation.values)
          .unwrap_or(Map([])),
          work,
        ),
      ),
    )
  } else {
    None
  }
  let opposite = match side {
    0 => 1
    1 => 0
    2 => 3
    _ => 2
  }
  let edge = if other is Some((next, adjacent)) {
    let own_priority = style.border_priority[side]
    let other_priority = adjacent.border_priority[opposite]
    let own = style.borders[side].strength()
    let adjacent_strength = adjacent.borders[opposite].strength()
    let wins = if own_priority != other_priority {
      own_priority > other_priority
    } else if own != adjacent_strength {
      own > adjacent_strength
    } else {
      address.row > next.row ||
      (address.row == next.row && address.column > next.column)
    }
    if wins {
      style.borders[side]
    } else if inside {
      return None
    } else {
      adjacent.borders[opposite]
    }
  } else {
    style.borders[side]
  }
  guard edge.width() > 0 else { return None }
  let width = edge.width() / 0.75
  let adjacent_width = fn(side : Int32) {
    other.map(item => item.1.borders[side].width() / 0.75).unwrap_or(0)
  }
  if side <= 1 {
    let before = (style.borders[2].width() / 0.75).max(adjacent_width(2))
    let after = (style.borders[3].width() / 0.75).max(adjacent_width(3))
    let start = if before > width {
      before - 1
    } else if before > 1 {
      -1.0
    } else {
      0.0
    }
    let end = if after > width { -2.0 } else if after > 2 { 1.0 } else { 0.0 }
    Some(
      (
        edge,
        {
          x: rect.x + (if side == 1 { rect.width } else { 0.0 }),
          y: rect.y + start * 0.75,
          width: 0,
          height: rect.height + (1 + end - start) * 0.75,
        },
      ),
    )
  } else {
    // Native horizontal junctions use the upper cell's right edge; the first row has no upper cell.
    let upper = if side == 3 { Some(style) } else { other.map(item => item.1) }
    let lower = if side == 2 {
      style.borders[0].width() / 0.75
    } else {
      adjacent_width(0)
    }
    let (start, end) = if upper is Some(upper) {
      let left = (upper.borders[0].width() / 0.75).max(lower)
      let right = upper.borders[1].width() / 0.75
      (
        if width > left {
          if left > 1 {
            -1.0
          } else {
            0.0
          }
        } else if left > 2 {
          2.0
        } else {
          1.0
        },
        if width > right {
          if right > 2 {
            1.0
          } else {
            0.0
          }
        } else if right > 1 {
          -2.0
        } else {
          -1.0
        },
      )
    } else {
      (1.0, -1.0)
    }
    Some(
      (
        edge,
        {
          x: rect.x + start * 0.75,
          y: rect.y + (if side == 3 { rect.height } else { 0.0 }),
          width: rect.width + (1 + end - start) * 0.75,
          height: 0,
        },
      ),
    )
  }
}
