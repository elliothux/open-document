///|
fn selection_text_changes(
  object : Object,
  selection : Selection,
  text : String,
) -> (Array[@xml.SourceChange], Selection) raise @failure.Failure {
  guard object.table is Some(table) else {
    return text_changes(object, selection, text)
  }
  let range = table.range(selection)
  if !range.multiple() {
    return text_changes(object, selection, text)
  }
  let changes : Array[@xml.SourceChange] = []
  let mut after = selection
  for row in range.top..<=range.bottom {
    for column in range.left..<=range.right {
      if !table.rows[row].cells[column].owner() {
        continue
      }
      let cell = object.table_cell(table.rows[row].cells[column])
      let first = row == range.top && column == range.left
      let (edits, next) = text_changes(
        cell,
        { ..selection, anchor: 0, focus: cell.text().length(), },
        if first {
          text
        } else {
          ""
        },
      )
      changes.append(edits)
      if first {
        let offset = table.cell_offset(row, column)
        after = {
          ..selection,
          anchor: offset + next.focus,
          focus: offset + next.focus,
        }
      }
    }
  }
  (changes, after)
}

///|
fn DrawingTable::copied_cells(
  self : DrawingTable,
  range : TableRange,
) -> String {
  let rows : Array[String] = []
  for row in range.top..<=range.bottom {
    let cells : Array[String] = []
    for column in range.left..<=range.right {
      if !self.rows[row].cells[column].owner() {
        continue
      }
      cells.push(
        self.rows[row].cells[column].paragraphs
        .map(p => p.runs.map(run => run.text).join(""))
        .join("\n"),
      )
    }
    if !cells.is_empty() {
      rows.push(cells.join("\t"))
    }
  }
  rows.join("\n").replace_all(old="\u2028", new="\n")
}
