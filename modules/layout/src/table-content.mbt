///|
/// Native cell order, including tables between direct cell paragraphs.
pub fn Table::paragraphs(self : Table) -> Array[Paragraph] {
  let result : Array[Paragraph] = []
  for row, cells in self.rows {
    for column, cell in cells {
      for index in 0..<=cell.length() {
        for nested in self.nestedTables {
          if nested.row == row &&
            nested.column == column &&
            nested.table.beforeParagraph == index {
            result.append(nested.table.paragraphs())
          }
        }
        if index < cell.length() {
          result.push(cell[index])
        }
      }
    }
  }
  result
}

///|
pub fn Table::map_paragraphs(
  self : Table,
  transform : (Paragraph) -> Paragraph raise @failure.Failure,
) -> Table raise @failure.Failure {
  {
    ..self,
    rows: self.rows.map(row => row.map(cell => cell.map(transform))),
    nestedTables: self.nestedTables.map(nested => {
      ..nested,
      table: nested.table.map_paragraphs(transform),
    }),
  }
}

///|
fn Table::check_nested(
  self : Table,
  depth~ : Int32 = 0,
) -> Unit raise @failure.Failure {
  guard depth <= 8 && self.nestedTables.length() <= 4096 else {
    @failure.reject("limit-exceeded", "Nested table budget exceeded")
  }
  self.check_grid()
  let positions : Map[(Int32, Int32), Int32] = Map([])
  for child in self.nestedTables {
    guard self.rows.get(child.row).bind(row => row.get(child.column))
      is Some(cell) &&
      self.rowSpans[child.row][child.column] > 0 &&
      child.table.beforeParagraph >=
      positions.get((child.row, child.column)).unwrap_or(0) &&
      child.table.beforeParagraph <= cell.length() else {
      @failure.reject("invalid-table", "Invalid nested table position")
    }
    positions[(child.row, child.column)] = child.table.beforeParagraph
    child.table.check_nested(depth=depth + 1)
  }
}
