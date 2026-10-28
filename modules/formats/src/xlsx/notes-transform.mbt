///|
fn SheetNotes::merge_note(self : SheetNotes, range : Range) -> CellNote? {
  let mut kept : CellNote? = None
  for note in self.entries {
    if range.contains(note.address) &&
      (
        kept is None ||
        (
          kept is Some(previous) &&
          note.address.row <= previous.address.row &&
          note.address.column < previous.address.column
        )
      ) {
      kept = Some(note)
    }
  }
  kept
}

///|
fn SheetNotes::merge_discarded(self : SheetNotes, range : Range) -> Int32 {
  (self.entries.filter(note => range.contains(note.address)).length() - 1).max(
    0,
  )
}

///|
fn update_note_addresses(
  notes : SheetNotes,
  addresses : Map[String, Address?],
  parts : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
  threaded~ : Bool = false,
) -> Unit raise @failure.Failure {
  let comments : Array[@xml.SourceChange] = []
  let shapes : Array[@xml.SourceChange] = []
  for note in notes.entries {
    guard addresses.get(note.address.name()) is Some(next) else { continue }
    if next == Some(note.address) {
      continue
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
        for
          (name, before, after) in [
            ("Row", note.address.row, address.row),
            ("Column", note.address.column, address.column),
          ] {
          if before != after {
            let node = vml_child(tree, data.id, note_excel_uri, name).unwrap()
            shapes.append(axis_text_change(tree, node, (after - 1).to_string()))
          }
        }
      } else {
        shapes.push(sheet_node_removal(tree, shape))
      }
    }
  }
  if !comments.is_empty() {
    let (document, edit) = notes.tree.document.edit_source(comments)
    ignore(read_cell_notes(Tree::new(document), threaded~))
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
