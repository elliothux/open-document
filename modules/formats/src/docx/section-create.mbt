///|
fn WordTree::position_section(
  self : WordTree,
  position : Position,
) -> Int32 raise @failure.Failure {
  let offset = self.nodes[position.paragraph].start
  for index, section in self.page_sections() {
    if section.map(id => self.nodes[id].start >= offset).unwrap_or(true) {
      return index
    }
  }
  @failure.reject("invalid-position", "Position has no page section")
}

///|
fn Session::prepare_section_position(
  self : Session,
  document : @xml.Document,
  tree : WordTree,
  position : Position,
) -> (PreparedEdit, Int32) raise @failure.Failure {
  let paragraph = tree.nodes[position.paragraph]
  let parent = tree.nodes[paragraph.parent]
  let selection : Selection = { anchor: position, focus: position, }
  if parent.name == "body" && parent.uri == word_uri {
    let prepared = self.prepare_structural_range(selection, "\n", notes=true)
    return (prepared, paragraph.id)
  }
  guard parent.uri == word_uri && parent.name == "tc" else {
    @failure.reject(
      "protected-content", "Section breaks require body text or a body table",
    )
  }
  let grid = self.table_grid(tree, selection, notes=true)
  if grid.row > 0 {
    return self.prepare_table_split(document, tree, grid)
  }
  let table = tree.nodes[grid.table]
  let body = tree.nodes[table.parent]
  let index = tree.children[body.id].search(table.id).unwrap()
  let (candidate, edit) = document.edit_source([
    {
      node: body.id,
      offset: table.start - body.start,
      length: 0,
      xml: "<od:p xmlns:od='\{word_uri}'/>",
    },
  ])
  let current = WordTree::new(candidate)
  let boundary = current.children[body.id][index]
  let caret = table_position(current.table_children(grid.cells[0][0], "p")[0])
  (
    {
      edit: {
        xml: [edit],
        parts: Map([]),
        created: Map([]),
        created_media: Map([]),
        before: self.selection,
        after: Some({ anchor: caret, focus: caret, }),
        paragraphs: [boundary, caret.paragraph],
        bytes: edit_bytes(edit),
      },
      document: candidate,
      typing_text: None,
      join_group: false,
    },
    boundary,
  )
}

///|
/// Inserts a native section break at the selection start as one complete source edit.
pub fn Session::insert_section_break(
  self : Session,
  revision : Int32,
  kind : String,
  probe~ : @layout.TextProbe,
  profile~ : Map[String, String],
  images~ : @layout.Images,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  guard ["nextPage", "oddPage", "evenPage", "continuous"].contains(kind) else {
    @failure.reject("invalid-operation", "Unsupported section break type")
  }
  guard self.selection is Some(selection) else {
    @failure.reject("invalid-position", "Select a document position first")
  }
  self.check_position(selection.anchor)
  self.check_position(selection.focus)
  let document = self.document()
  let tree = WordTree::new(document)
  guard tree.page_sections().length() < 1024 else {
    @failure.reject("limit-exceeded", "Section count exceeds page budget")
  }
  let position = if tree.nodes[selection.anchor.paragraph].start <
    tree.nodes[selection.focus.paragraph].start ||
    (
      selection.anchor.paragraph == selection.focus.paragraph &&
      selection.anchor.offset <= selection.focus.offset
    ) {
    selection.anchor
  } else {
    selection.focus
  }
  let index = tree.position_section(position)
  let section = self.editable_page_section(tree, target=Some(index))
  ignore(tree.section_numbering(section))
  let copy = section
    .map(id => tree.standalone_markup(document, id))
    .unwrap_or("<od:sectPr xmlns:od='\{word_uri}'/>")
  let (prepared, boundary) = self.prepare_section_position(
    document, tree, position,
  )
  let tree = WordTree::new(prepared.document)
  let (candidate, added, section) = page_section(
    prepared.document,
    tree,
    tree.page_sections()[index],
  )
  let current = WordTree::new(candidate)
  let changes = [current.paragraph_section_change(boundary, copy)]
  for id in current.children[section] {
    let node = current.nodes[id]
    if node.uri == word_uri &&
      ["headerReference", "footerReference"].contains(node.name) {
      changes.push({
        node: section,
        offset: node.start - current.nodes[section].start,
        length: node.end - node.start,
        xml: "",
      })
    }
  }
  if current.child(section, "pgNumType") is Some(id) &&
    current.nodes[id].attribute("start", uri=word_uri) is Some(_) {
    let markup = property_markup(
      current,
      candidate,
      Some(id),
      "pgNumType",
      Some({ "start": None }),
    )
    changes.push(
      properties_change(current, candidate, section, "pgNumType", markup).unwrap(),
    )
  }
  if current.section_start_change(candidate, section, kind) is Some(change) {
    changes.push(change)
  }
  let (candidate, edit) = candidate.edit_source(changes)
  let view = { ..self, document: Some(candidate), }
  let layout = @layout.paginate(
    probe,
    view.flow_from(candidate),
    profile,
    images,
  )
  guard layout.diagnostics.is_empty() else {
    @failure.reject(
      "unsupported-layout", "Section creation requires a complete layout",
    )
  }
  ignore(view.page_positioned(layout, probe))
  let edits = [..prepared.edit.xml, ..added, edit]
  let bytes = edits.fold(init=0, (total, step) => {
    let size = edit_bytes(step)
    guard size <= history_byte_limit - total else {
      @failure.reject(
        "limit-exceeded", "Section creation exceeds history budget",
      )
    }
    total + size
  })
  let pending = self.typing_format
  self.commit_edit({ ..prepared.edit, xml: edits, bytes, }, candidate)
  self.typing_format = pending
  self.typing_text = prepared.typing_text
  self.edit_result(prepared.edit.paragraphs)
}
