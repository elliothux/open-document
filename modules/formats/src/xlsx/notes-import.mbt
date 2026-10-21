///|
fn Session::insert_note_fragments(
  self : Session,
  target : Sheet,
  document : @xml.Document,
  incoming : SheetNotes,
  destinations : Map[String, Address],
  parts : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
  created : Map[String, @xml.Document],
) -> @xml.Document raise @failure.Failure {
  let moved = incoming.entries.filter(note => {
    destinations.contains(note.address.name())
  })
  if moved.is_empty() {
    return document
  }
  let candidate = { ..self, parts, }
  let previous = candidate.read_sheet_notes(target)
  let entries = previous.map(notes => notes.entries).unwrap_or([])
  guard entries.length() + moved.length() <= 4096 &&
    entries.fold(init=0L, (sum, note) => sum + note.text.length().to_int64()) +
    moved.fold(init=0L, (sum, note) => sum + note.text.length().to_int64()) <=
    1048576 else {
    @failure.reject("limit-exceeded", "Transferred cell notes exceed budget")
  }
  let part = previous
    .map(notes => notes.part)
    .unwrap_or_else(() => {
      self.create_sheet_resource(
        target.id,
        "comments",
        "<comments xmlns=\"\{spreadsheet_uri}\"><authors/><commentList/></comments>",
        parts,
        created,
        edits,
      ).0
    })
  let tree = Tree::new(
    parts.get(part).unwrap_or_else(() => self.part_xml(part)),
  )
  let root = tree.root("comments")
  let authors = previous.map(notes => notes.authors.copy()).unwrap_or([])
  let author_xml = StringBuilder()
  let note_xml = StringBuilder()
  let shape_xml = StringBuilder()
  let guids : Map[String, Bool] = Map([])
  for note in entries {
    if note.node.attribute("guid") is Some(guid) && !guid.is_empty() {
      guids[guid] = true
    }
  }
  let mut sheet_document = document
  let (vml_part, vml) = if previous.bind(notes => notes.vml)
    is Some((path, tree, _)) {
    (path, tree)
  } else {
    guard entries.all(note => note.node.attribute("shapeId") is None) else {
      @failure.reject(
        "protected-content", "Imported note shape identities require VML ownership support",
      )
    }
    let (path, relation) = self.create_sheet_resource(
      target.id,
      "vmlDrawing",
      note_vml_document(entries.map(note => note.address)),
      parts,
      created,
      edits,
    )
    let (next, edit) = insert_sheet_drawing(sheet_document, relation)
    sheet_document = next
    edits.push((target.id, edit))
    (path, Tree::new(parts[path]))
  }
  let ids : Map[String, Bool] = Map([])
  for node in vml.document.nodes() {
    if node.attribute("id") is Some(id) {
      ids[id.trim().to_owned()] = true
    }
  }
  let types : Map[String, String] = Map([])
  let mut units = 0L
  for note in moved {
    let address = destinations[note.address.name()]
    let author = authors
      .search(note.author)
      .unwrap_or_else(() => {
        guard authors.length() < 4096 else {
          @failure.reject(
            "limit-exceeded", "Transferred note authors exceed budget",
          )
        }
        let index = authors.length()
        authors.push(note.author)
        author_xml <+
          "<od:author xmlns:od=\"\{spreadsheet_uri}\">\{encode_text(note.author)}</od:author>"
        index
      })
    if note.node.attribute("guid") is Some(guid) && !guid.is_empty() {
      guard !guids.contains(guid) else {
        @failure.reject(
          "protected-content", "Transferred note identities collide",
        )
      }
      guids[guid] = true
    }
    let (shape, id) = moved_note_shape(incoming, note, address, vml, ids, types)
    shape_xml.write_string(shape)
    let changes = metadata_changes(note.node, [
      ("ref", address.name()),
      ("authorId", author.to_string()),
    ])
    if note.node.attribute("shapeId") is Some(shape_id) {
      guard incoming.vml is Some((_, _, shapes)) else {
        @failure.reject(
          "protected-content", "Transferred note shape identity has no VML owner",
        )
      }
      let old = shapes[note.address.name()].attribute("id").unwrap()
      guard old.strip_prefix("_x0000_s").map(value => value == shape_id) ==
        Some(true) else {
        @failure.reject(
          "protected-content", "Transferred note shape identity is unresolved",
        )
      }
      changes.append(metadata_changes(note.node, [("shapeId", id.to_string())]))
    }
    let xml = style_markup(incoming.tree, note.node, changes~)
    units += (xml.length() + shape.length()).to_int64()
    guard units <= 2097152 else {
      @failure.reject(
        "limit-exceeded", "Transferred note source exceeds budget",
      )
    }
    note_xml.write_string(xml)
  }
  let changes = [
    insertion(tree.one(root.id, "commentList").unwrap(), note_xml.to_string()),
  ]
  if !author_xml.is_empty() {
    changes.push(
      insertion(tree.one(root.id, "authors").unwrap(), author_xml.to_string()),
    )
  }
  let (next, edit) = tree.document.edit_source(join_insertions(changes))
  ignore(read_cell_notes(Tree::new(next)))
  parts[part] = next
  edits.push((part, edit))
  let (next, edit) = vml.document.edit_source([
    insertion(vml.document.nodes()[0], shape_xml.to_string()),
  ])
  ignore(vml_note_shapes(Tree::new(next)))
  parts[vml_part] = next
  edits.push((vml_part, edit))
  let candidate = { ..self, parts, }
  ignore(candidate.read_sheet_notes({ ..target, document: sheet_document, }))
  sheet_document
}
