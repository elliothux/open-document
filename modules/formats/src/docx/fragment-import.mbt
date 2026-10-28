///|
fn Session::read_body_fragment(
  self : Session,
  xml : String,
  parts : Map[String, @xml.Document],
  edits : Map[String, Array[@xml.Edit]],
  created : Map[String, @xml.Document],
  media : Map[String, Bytes],
  added : Map[String, Bytes],
) -> @xml.Document raise @failure.Failure {
  let limit = self.opc.budget.entry_bytes.min(history_byte_limit / 2)
  guard !xml.is_empty() && xml.length() <= limit else {
    @failure.reject(
      "limit-exceeded", "Rich document fragment exceeds source budget",
    )
  }
  let document = @xml.Document::parse(
    @utf8.encode(
      "<od:document xmlns:od=\"\{word_uri}\">" + xml + "</od:document>",
    ),
    "body-fragment",
    self.opc.budget.xml_depth,
    self.opc.budget.entry_bytes,
  )
  let document = self.import_fragment_citations(document, parts, edits, created)
  let document = self.import_fragment_notes(document, parts, edits, created)
  let document = self.import_fragment_numbering(document, parts, edits, created)
  let document = self.import_fragment_links(document, parts, edits, created)
  let document = self.import_fragment_bookmarks(document)
  let document = self.import_fragment_drawing_links(
    document, parts, edits, created,
  )
  let (document, pictures) = self.import_fragment_drawings(
    document, parts, edits, created, media, added,
  )
  let tree = WordTree::new(document)
  self.fragment_math_nodes(document, pictures)
  guard tree.children[0] is [body] &&
    tree.nodes[body].uri == word_uri &&
    tree.nodes[body].name == "body" &&
    !tree.children[body].is_empty() &&
    tree.children[body].length() <= 1024 &&
    tree.children[body].all(id => {
      tree.nodes[id].uri == word_uri &&
      ["p", "tbl"].contains(tree.nodes[id].name)
    }) else {
    @failure.reject(
      "invalid-operation", "Rich text requires one body containing supported paragraphs or tables",
    )
  }
  check_fragment_content(
    tree,
    tree.descendants(body),
    pictures,
    fields=true,
    notes=true,
  )
  let view = { ..self, parts, media, }
  let flow = view.flow_from(document)
  guard flow.paragraphs.length() + flow.tables.length() ==
    tree.children[body].length() &&
    flow.tables.length() <= 32 &&
    flow.paragraphs.all(p => p.readOnlyReason.is_empty()) else {
    @failure.reject(
      "protected-content", "Rich document fragment contains unsupported paragraphs",
    )
  }
  let mut cells = 0L
  for table in flow.tables {
    ignore(view.check_fragment_table(tree, table, notes=true))
    cells += table.rows.length().to_int64() * table.widths.length().to_int64()
    guard cells <= 4096L else {
      @failure.reject("limit-exceeded", "Rich body tables exceed 4096 cells")
    }
  }
  document
}

///|
/// Preflights copied image resources without changing document state.
pub fn Session::body_fragment_images(
  self : Session,
  revision : Int32,
  fragment : String,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let parts = self.parts.copy()
  let edits : Map[String, Array[@xml.Edit]] = Map([])
  let created : Map[String, @xml.Document] = Map([])
  let media = self.media.copy()
  let added : Map[String, Bytes] = Map([])
  ignore(self.read_body_fragment(fragment, parts, edits, created, media, added))
  let view = { ..self, parts, media, }
  let images : Array[Json] = []
  for rel in view.relationships() {
    if rel.owner == self.main && added.get(rel.target) is Some(bytes) {
      images.push({ "key": rel.id, "bytes": @base64.encode(bytes) })
    }
  }
  { "revision": revision, "images": images }
}
