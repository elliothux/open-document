///|
fn fill_remainder(
  source : Range,
  cleared : Range,
  direction : String,
) -> Range raise @failure.Failure {
  guard source.contains({ row: cleared.top, column: cleared.left, }) &&
    source.contains({ row: cleared.bottom, column: cleared.right, }) &&
    (if direction == "up" {
      cleared.left == source.left &&
      cleared.right == source.right &&
      cleared.bottom == source.bottom
    } else if direction == "left" {
      cleared.top == source.top &&
      cleared.bottom == source.bottom &&
      cleared.right == source.right
    } else {
      false
    }) else {
    @failure.reject(
      "invalid-operation", "Shrink must clear trailing rows or columns of its source",
    )
  }
  if source == cleared {
    source
  } else if direction == "up" {
    { ..source, bottom: cleared.top - 1, }
  } else {
    { ..source, right: cleared.left - 1, }
  }
}

///|
fn Session::shrink_fill(
  self : Session,
  sheet : String,
  source : String,
  range : String,
  direction : String,
) -> Json raise @failure.Failure {
  let source = Range::parse(source)
  let cleared = Range::parse(range)
  let selected = fill_remainder(source, cleared, direction)
  guard (source.bottom - source.top + 1).to_int64() *
    (source.right - source.left + 1).to_int64() <=
    4096 else {
    @failure.reject("limit-exceeded", "Fill shrink exceeds 4096 cells")
  }
  let index = self.sheet_index(sheet)
  let current = self.sheets[index]
  self.check_fill_cells(current, [source])
  self.check_fill_resources(current, source)
  let updates : Map[String, CellContent] = Map([])
  for row in cleared.top..<=cleared.bottom {
    for column in cleared.left..<=cleared.right {
      let address : Address = { row, column, }
      if current.cells.get(address.name()) is Some(cell) &&
        (cell.value != Blank || cell.formula is Some(_)) {
        updates[address.name()] = {
          value: Blank,
          formula: None,
          keep_shared: false,
        }
      }
    }
  }
  if updates.is_empty() {
    return self.select(self.revision, sheet, selected.name())
  }
  self.commit_fill(index, selected, updates, Map([]))
}
