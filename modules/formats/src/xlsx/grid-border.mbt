///|
fn visible_neighbor(indices : Array[Int], value : Int, after : Bool) -> Int? {
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
fn CellBorder::strength(self : CellBorder) -> Int {
  match self.style {
    "thin" => 1
    "medium" => 2
    "thick" => 3
    "double" => 4
    _ => 0
  }
}

///|
// Resolve shared edges once, including hidden axes and derived table borders.
fn Session::border_wins(
  self : Session,
  style : CellStyle,
  address : Address,
  range : Range,
  side : Int,
  rows : Array[Int],
  columns : Array[Int],
  conditional : ConditionalRules,
  index : Int,
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
