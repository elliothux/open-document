///|
fn Session::set_note(
  self : Session,
  id : String,
  cell : String,
  text : String?,
  author : String,
) -> Json raise @failure.Failure {
  let index = self.sheet_index(id)
  let sheet = self.sheets[index]
  let reason = self.dimension_reason(sheet)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let requested = Address::parse(cell)
  let range = sheet.merge_target({
    top: requested.row,
    bottom: requested.row,
    left: requested.column,
    right: requested.column,
  })
  let address : Address = { row: range.top, column: range.left, }
  let notes = self.read_sheet_notes(sheet)
  let entries = notes.map(n => n.entries).unwrap_or([])
  let previous = entries.iter().find_first(n => n.address == address)
  let text = text.map(text => {
    guard text.length() <= 32767 &&
      !text.trim().is_empty() &&
      @xml.valid_text(text) else {
      @failure.reject(
        "invalid-text", "Cell notes require nonempty valid text within 32767 UTF-16 units",
      )
    }
    text.replace_all(old="\r\n", new="\n").replace_all(old="\r", new="\n")
  })
  if previous.map(n => n.text) == text {
    return self.query()
  }
  guard entries.length() +
    (if previous is None && text is Some(_) { 1 } else { 0 }) <=
    4096 &&
    entries
    .iter()
    .fold(
      init=text.map(t => t.length()).unwrap_or(0) -
        previous.map(n => n.text.length()).unwrap_or(0),
      (sum, n) => sum + n.text.length(),
    ) <=
    1048576 else {
    @failure.reject("limit-exceeded", "Cell notes exceed budget")
  }
  let parts = self.parts.copy()
  let created : Map[String, @xml.Document] = Map([])
  let edits : Array[(String, @xml.Edit)] = []
  let mut sheet_document = sheet.document
  if notes is Some(notes) {
    let tree = notes.tree
    let changes : Array[@xml.SourceChange] = []
    match (previous, text) {
      (Some(note), Some(text)) => {
        let node = note.body
        let markup = note_body(tree, note, text)
        changes.push(
          if node.empty {
            insertion(node, markup)
          } else {
            {
              node: node.id,
              offset: node.opening_end - node.start,
              length: node.closing_start - node.opening_end,
              xml: markup,
            }
          },
        )
      }
      (Some(note), None) => changes.push(sheet_node_removal(tree, note.node))
      (None, Some(text)) => {
        check_note_author(author)
        let author_index = if notes.authors.search(author) is Some(index) {
          index
        } else {
          guard notes.authors.length() < 4096 else {
            @failure.reject("limit-exceeded", "Cell note authors exceed budget")
          }
          let root = tree.root("comments")
          changes.push(
            insertion(
              tree.one(root.id, "authors").unwrap(),
              "<od:author xmlns:od=\"\{spreadsheet_uri}\">\{encode_text(author)}</od:author>",
            ),
          )
          notes.authors.length()
        }
        changes.push(
          insertion(
            tree.one(tree.root("comments").id, "commentList").unwrap(),
            note_source(address, text, author_index),
          ),
        )
      }
      (None, None) => ()
    }
    let (document, edit) = tree.document.edit_source(join_insertions(changes))
    parts[notes.part] = document
    edits.push((notes.part, edit))
  } else if text is Some(text) {
    check_note_author(author)
    ignore(
      self.create_sheet_resource(
        id,
        "comments",
        "<comments xmlns=\"\{spreadsheet_uri}\"><authors><author>\{encode_text(author)}</author></authors><commentList>\{note_source(address, text, 0)}</commentList></comments>",
        parts,
        created,
        edits,
      ),
    )
  }
  let vml = notes.bind(n => n.vml)
  if vml is Some((part, tree, shapes)) {
    let change = match (previous, text) {
      (Some(_), None) =>
        shapes.get(address.name()).map(n => sheet_node_removal(tree, n))
      (None, Some(_)) => {
        let ids : Map[String, Bool] = Map([])
        for n in tree.document.nodes() {
          if n.attribute("id") is Some(id) {
            ids[id.trim().to_owned()] = true
          }
        }
        let next = for i in 1025..<=21504 {
          if !ids.contains("_x0000_s\{i}") {
            break i
          }
        } nobreak {
          @failure.reject("limit-exceeded", "VML note identities exhausted")
        }
        let shape_type = tree.document
          .nodes()
          .iter()
          .find_first(n => {
            n.uri == note_vml_uri &&
            n.name == "shapetype" &&
            n.attribute("spt", uri=note_office_uri) == Some("202")
          })
          .unwrap()
          .attribute("id")
          .unwrap()
        Some(
          insertion(
            tree.document.nodes()[0],
            note_vml_shape(address, next, shape_type~),
          ),
        )
      }
      _ => None
    }
    if change is Some(change) {
      let (document, edit) = tree.document.edit_source([change])
      parts[part] = document
      edits.push((part, edit))
    }
  } else if previous is None && text is Some(_) {
    guard entries.all(n => n.node.attribute("shapeId") is None) else {
      @failure.reject(
        "protected-content", "Imported note shape identities require VML ownership support",
      )
    }
    let addresses = entries.map(n => n.address)
    addresses.push(address)
    let (_, relation) = self.create_sheet_resource(
      id,
      "vmlDrawing",
      note_vml_document(addresses),
      parts,
      created,
      edits,
    )
    let (document, edit) = insert_note_vml(sheet.document, relation)
    sheet_document = document
    edits.push((id, edit))
  }
  let sheets = self.sheets.copy()
  sheets[index] = Sheet::read(
    id,
    sheet.name,
    sheet.state,
    sheet_document,
    self.strings,
    self.styles.length(),
  )
  let anchor = self.anchor
  let focus = self.focus
  self.commit(
    sheets,
    self.workbook,
    self.calculation.unwrap(),
    edits,
    self.selection,
    parts~,
    created_parts=created,
  )
  self.anchor = anchor
  self.focus = focus
  self.query()
}

///|
fn check_note_author(author : String) -> Unit raise @failure.Failure {
  guard !author.trim().is_empty() &&
    author.length() <= 255 &&
    @xml.valid_text(author) &&
    author.iter().all(c => c >= ' ') else {
    @failure.reject(
      "invalid-operation", "New cell notes require an explicit bounded author",
    )
  }
}
