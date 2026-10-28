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
  if self.style == "double" {
    for offset in [-0.75, 0.75] {
      let line = if rect.width == 0 {
        { ..rect, x: rect.x + offset, }
      } else {
        { ..rect, y: rect.y + offset, }
      }
      strokes.push(Stroke(line, self.color, 0.75))
    }
  } else {
    let dash = self.dash()
    if dash.is_empty() {
      strokes.push(Stroke(rect, self.color, self.width()))
    } else {
      strokes.push(
        Path(
          [
            @layout.PathSegment::Move(rect.x, rect.y),
            Line(rect.x + rect.width, rect.y + rect.height),
          ],
          "",
          self.color,
          self.width(),
          { fillAlpha: 1, strokeAlpha: 1, dash, cap: 0, join: 0, miter: 10, },
        ),
      )
    }
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
// Resolve shared edges once, including hidden axes and derived table borders.
fn Session::border_wins(
  self : Session,
  style : CellStyle,
  address : Address,
  range : Range,
  side : Int32,
  rows : Array[Int32],
  columns : Array[Int32],
  conditional : ConditionalRules,
  index : Int32,
  work : FormulaWork,
) -> Bool raise @failure.Failure {
  let sheet = self.sheets[index]
  let neighbor = match side {
    0 | 1 => {
      let after = (side == 1) != sheet.view.rtl
      visible_neighbor(
        columns,
        if after {
          range.right
        } else {
          range.left
        },
        after,
      ).map(column => { ..address, column, })
    }
    _ => {
      let after = side == 3
      visible_neighbor(
        rows,
        if after {
          range.bottom
        } else {
          range.top
        },
        after,
      ).map(row => { ..address, row, })
    }
  }
  guard neighbor is Some(neighbor) else { return true }
  let neighbor_range = sheet.cell_range(neighbor)
  let neighbor = Address::{
    row: neighbor_range.top,
    column: neighbor_range.left,
  }
  let other = conditional.applied(
    self.merged_style(sheet, neighbor_range),
    neighbor,
    self.sheets,
    index,
    self.calculation.map(calculation => calculation.values).unwrap_or(Map([])),
    work,
  )
  let opposite = match side {
    0 => 1
    1 => 0
    2 => 3
    _ => 2
  }
  if style.border_priority[side] != other.border_priority[opposite] {
    return style.border_priority[side] > other.border_priority[opposite]
  }
  let own = style.borders[side].strength()
  let adjacent = other.borders[opposite].strength()
  if own != adjacent {
    return own > adjacent
  }
  address.row > neighbor.row ||
  (address.row == neighbor.row && address.column > neighbor.column)
}
