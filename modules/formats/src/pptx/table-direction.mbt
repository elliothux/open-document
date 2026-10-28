///|
fn Session::set_table_direction(
  self : Session,
  rtl : Bool,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  guard self.selection.objects.length() == 1 else {
    @failure.reject(
      "invalid-operation", "Select one table to change its direction",
    )
  }
  let original = self.current()
  let object = original.object(self.selection.object)
  guard object.table is Some(table) else {
    @failure.reject("protected-content", "Select an editable table")
  }
  let reason = self.table_geometry_reason(object, self.selection)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  if table.rtl == rtl {
    return self.query()
  }
  let source = object.source
    .child("graphic")
    .unwrap()
    .child("graphicData")
    .unwrap()
    .child("tbl")
    .unwrap()
  let value = if rtl { "1" } else { "0" }
  let changes = [
    if source.child("tblPr") is Some(properties) {
      attribute_change(properties, "rtl", value)
    } else {
      table_source_change(
        source.child("tblGrid").unwrap(),
        "<a:tblPr xmlns:a='\{drawing_uri}' rtl='\{value}'/>",
        before=Some(true),
      )
    },
  ]
  let (candidate, edit) = self.prepare_table(
    original,
    changes,
    object.id,
    probe,
    profile,
  )
  self.commit(candidate, edit, self.selection, probe~, profile~)
  self.query()
}

///|
fn DrawingTable::rtl_navigation(
  self : DrawingTable,
  text : TextGeometry,
  position : Int32,
  direction : String,
) -> Int32? raise @failure.Failure {
  let (r, c) = self.cell_at(position)
  let cell = self.rows[r].cells[c]
  let start = self.cell_offset(r, c)
  let end = start +
    cell.paragraphs.fold(init=-1, (sum, p) => sum + paragraph_length(p) + 1)
  if direction == "left" || direction == "right" {
    if (direction == "left" && position != start) ||
      (direction == "right" && position != end) {
      return None
    }
    let column = if direction == "left" { c + cell.column_span } else { c - 1 }
    if column < 0 || column >= self.widths.length() {
      return Some(position)
    }
    let (row, column) = self.owners[r][column]
    let next = self.cell_offset(row, column)
    return Some(
      if direction == "left" {
        next
      } else {
        next +
        self.rows[row].cells[column].paragraphs.fold(init=-1, (sum, p) => {
          sum + paragraph_length(p) + 1
        })
      },
    )
  }
  guard direction == "up" || direction == "down" else { return None }
  let lines = text.lines.filter(line => line.start >= start && line.end <= end)
  let mut index = -1
  for i, line in lines {
    if line.carets.any(caret => caret.offset == position) {
      index = i
      break
    }
  }
  guard index >= 0 else { return Some(position) }
  let line = lines[index]
  let caret = line.carets
    .iter()
    .find_first(caret => caret.offset == position)
    .unwrap()
  let point = text
    .line_matrix(line)
    .point(line.x + caret.after, line.y + line.height / 2)
  let next = index + (if direction == "up" { -1 } else { 1 })
  if next >= 0 && next < lines.length() {
    return Some(
      closest_caret({ ..text, lines: [lines[next]], }, point.0, point.1),
    )
  }
  let row = if direction == "up" { r - 1 } else { r + cell.row_span }
  if row < 0 || row >= self.rows.length() {
    return Some(position)
  }
  let (row, column) = self.owners[row][c]
  let first = self.cell_offset(row, column)
  let last = first +
    self.rows[row].cells[column].paragraphs.fold(init=-1, (sum, p) => {
      sum + paragraph_length(p) + 1
    })
  let lines = text.lines.filter(line => line.start >= first && line.end <= last)
  Some(
    if lines.is_empty() {
      first
    } else {
      closest_caret({ ..text, lines, }, point.0, point.1)
    },
  )
}
