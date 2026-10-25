///|
fn Object::table_hit_offset(
  self : Object,
  text : TextGeometry,
  x : Double,
  y : Double,
) -> Int raise @failure.Failure {
  let table = self.table.unwrap()
  let (px, py) = text.matrix.inverse().point(x, y)
  let px = if table.rtl { table.column_edge(0) - px } else { px }
  let mut row = table.rows.length() - 1
  let mut column = table.widths.length() - 1
  let mut edge = 0.0
  for index, item in table.rows {
    edge += item.height
    if py <= edge {
      row = index
      break
    }
  }
  edge = 0
  for index, width in table.widths {
    edge += width
    if px <= edge {
      column = index
      break
    }
  }
  let (row, column) = table.owners[row][column]
  let start = table.cell_offset(row, column)
  let end = start +
    table.rows[row].cells[column].paragraphs.fold(init=-1, (sum, p) => {
      sum + paragraph_length(p) + 1
    })
  let lines = text.lines.filter(line => line.start >= start && line.end <= end)
  if lines.is_empty() {
    return start
  }
  closest_caret({ ..text, lines, }, x, y)
}

///|
fn Object::table_range_polygon(
  self : Object,
  range : TableRange,
) -> Array[Json] {
  let table = self.table.unwrap()
  let x = table.column_left(range.left, range.right - range.left + 1)
  let y = table.rows[:range.top].fold(init=0.0, (sum, row) => sum + row.height)
  let width = table.widths[range.left:range.right + 1].fold(init=0.0, (
    sum,
    width,
  ) => sum + width)
  let height = table.rows[range.top:range.bottom + 1].fold(init=0.0, (sum, row) => {
    sum + row.height
  })
  polygon(self.geometry.unwrap().matrix, x, y, width, height)
}
