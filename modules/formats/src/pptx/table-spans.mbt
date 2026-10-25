///|
fn DrawingCell::owner(self : DrawingCell) -> Bool {
  !self.h_merge && !self.v_merge
}

///|
fn table_owners(
  rows : Array[DrawingRow],
  columns : Int,
) -> Array[Array[(Int, Int)]] raise @failure.Failure {
  let owners = rows.map(_ => Array::make(columns, (-1, -1)))
  for row, item in rows {
    for column, cell in item.cells {
      if !cell.owner() {
        continue
      }
      table_profile(
        row + cell.row_span <= rows.length() &&
        column + cell.column_span <= columns,
        "Table span exceeds its grid",
      )
      for r in row..<(row + cell.row_span) {
        for c in column..<(column + cell.column_span) {
          table_profile(owners[r][c] == (-1, -1), "Overlapping table spans")
          owners[r][c] = (row, column)
        }
      }
    }
  }
  for row, item in rows {
    for column, cell in item.cells {
      let (r, c) = owners[row][column]
      table_profile(r >= 0 && c >= 0, "Orphan table continuation")
      let owner = rows[r].cells[c]
      table_profile(
        cell.h_merge == (column > c) &&
        cell.v_merge == (row > r) &&
        cell.column_span == (if column == c { owner.column_span } else { 1 }) &&
        cell.row_span ==
        (if row == r && column == c { owner.row_span } else { 1 }),
        "Inconsistent table continuation spans",
      )
      table_profile(
        cell.owner() ||
        cell.paragraphs.all(p => p.runs.all(run => run.text.is_empty())),
        "Table continuation contains hidden text",
      )
    }
  }
  owners
}

///|
fn DrawingTable::width(
  self : DrawingTable,
  column : Int,
  cell : DrawingCell,
) -> Double {
  self.widths[column:column + cell.column_span].fold(init=0.0, (sum, width) => {
    sum + width
  })
}

///|
fn DrawingTable::height(
  self : DrawingTable,
  row : Int,
  cell : DrawingCell,
) -> Double {
  self.rows[row:row + cell.row_span].fold(init=0.0, (sum, row) => {
    sum + row.height
  })
}

///|
fn DrawingTable::column_edge(self : DrawingTable, column : Int) -> Double {
  let before = self.widths[:column].fold(init=0.0, (sum, width) => sum + width)
  if self.rtl {
    self.widths.fold(init=0.0, (sum, width) => sum + width) - before
  } else {
    before
  }
}

///|
fn DrawingTable::column_left(
  self : DrawingTable,
  column : Int,
  span : Int,
) -> Double {
  self.column_edge(if self.rtl { column + span } else { column })
}
