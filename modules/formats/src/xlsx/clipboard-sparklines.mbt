///|
pub(all) struct CopiedSparkline {
  cell : Address
  source : Range?
  kind : String
}

///|
fn CopiedCells::check_copied_sparklines(
  self : CopiedCells,
) -> Unit raise @failure.Failure {
  guard self.sparklines.length() <= 256 else {
    @failure.reject("limit-exceeded", "Copied sparklines exceed 256")
  }
  let bounds : Range = {
    top: self.top,
    left: self.left,
    bottom: self.top + self.cells.length() - 1,
    right: self.left + self.cells[0].length() - 1,
  }
  let occupied : Map[String, Bool] = Map([])
  for item in self.sparklines {
    guard bounds.contains(item.cell) &&
      !occupied.contains(item.cell.name()) &&
      ["line", "column", "winLoss"].contains(item.kind) &&
      !self.merges.any(range => {
        range.contains({
          row: item.cell.row - self.top + 1,
          column: item.cell.column - self.left + 1,
        })
      }) else {
      @failure.reject(
        "invalid-operation", "Invalid copied sparkline destination or type",
      )
    }
    occupied[item.cell.name()] = true
    if item.source is Some(range) {
      ignore(sparkline_source(range.name(), ""))
    }
  }
}

///|
fn CopiedCells::sparklines_at(
  self : CopiedCells,
  sheet : Sheet,
  target : Range,
  transpose : Bool,
) -> Array[Sparkline] raise @failure.Failure {
  let items = sheet.sparklines.items.filter(item => !target.contains(item.cell))
  guard items.length() + self.sparklines.length() <= 256 else {
    @failure.reject("limit-exceeded", "Pasted sparklines exceed 256")
  }
  for item in self.sparklines {
    let point = self.rule_range(
      {
        top: item.cell.row,
        bottom: item.cell.row,
        left: item.cell.column,
        right: item.cell.column,
      },
      target,
      transpose,
    )
    items.push({
      cell: { row: point.top, column: point.left, },
      // ONLYOFFICE cell paste shifts data coordinates and binds to the destination sheet.
      source: item.source.map(range => {
        range.sparkline_offset(target.top - self.top, target.left - self.left)
      }),
      owner: None,
      kind: item.kind,
    })
  }
  if items.length() == sheet.sparklines.items.length() &&
    items.all(item => sheet.sparklines.items.contains(item)) {
    return sheet.sparklines.items
  }
  items.sort_by((a, b) => {
    if a.cell.row == b.cell.row {
      a.cell.column.compare(b.cell.column)
    } else {
      a.cell.row.compare(b.cell.row)
    }
  })
  items
}
