///|
fn shift_cell_notes(
  notes : SheetNotes,
  change : AxisChange,
  parts : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
) -> Unit raise @failure.Failure {
  let comments : Array[@xml.SourceChange] = []
  let shapes : Array[@xml.SourceChange] = []
  for note in notes.entries {
    let next = change.address(note.address)
    if next == Some(note.address) {
      continue
    }
    guard !change.insert || next is Some(_) else {
      @failure.reject(
        "invalid-operation", "Insertion would discard a cell note",
      )
    }
    if next is Some(address) {
      comments.append(metadata_changes(note.node, [("ref", address.name())]))
    } else {
      comments.push(sheet_node_removal(notes.tree, note.node))
    }
    if notes.vml is Some((_, tree, nodes)) {
      let shape = nodes[note.address.name()]
      if next is Some(address) {
        let data = vml_child(tree, shape.id, note_excel_uri, "ClientData").unwrap()
        let (name, value) = if change.rows {
          ("Row", address.row - 1)
        } else {
          ("Column", address.column - 1)
        }
        let node = vml_child(tree, data.id, note_excel_uri, name).unwrap()
        shapes.append(axis_text_change(tree, node, value.to_string()))
      } else {
        shapes.push(sheet_node_removal(tree, shape))
      }
    }
  }
  if !comments.is_empty() {
    let (document, edit) = notes.tree.document.edit_source(comments)
    ignore(read_cell_notes(Tree::new(document)))
    parts[notes.part] = document
    edits.push((notes.part, edit))
  }
  if !shapes.is_empty() && notes.vml is Some((part, tree, _)) {
    let (document, edit) = tree.document.edit_source(shapes)
    ignore(vml_note_shapes(Tree::new(document)))
    parts[part] = document
    edits.push((part, edit))
  }
}
