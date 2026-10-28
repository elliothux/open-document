///|
fn Session::capture_body_fragment(
  self : Session,
  selection : Selection,
  layout? : @layout.Layout,
) -> String raise @failure.Failure {
  let document = self.document()
  let tree = WordTree::new(document)
  let range = self.paragraph_range(
    tree,
    selection,
    structural=true,
    fields=true,
    math=true,
    tables=true,
    notes=true,
  )
  let fields = self.selection_field_values(tree, range, layout)
  let limit = self.opc.budget.entry_bytes.min(history_byte_limit / 2)
  let styles = self.styles([])
  let (numbering, numbers) = self.fragment_paragraph_numbering(
    tree,
    range.paragraphs,
    styles,
    limit,
  )
  let paragraphs = Map::from_array(range.paragraphs.map(id => (id, true)))
  let selected : Map[Int32, Bool] = Map([])
  for id, position in tree.inline_marker_positions() {
    if tree.is_bookmark(id) &&
      paragraphs.contains(position.paragraph) &&
      (
        position.paragraph != range.start.paragraph ||
        position.offset >= range.start.offset
      ) &&
      (
        position.paragraph != range.end.paragraph ||
        position.offset <= range.end.offset
      ) {
      selected[id] = true
    }
  }
  let markers = fragment_bookmark_nodes(tree, paragraphs, selected)
  let links = self.hyperlink_relationships()
  let bookmarks = tree.bookmark_targets()
  let flow = self.flow()
  let all = flow.paragraphs.copy()
  all.append(flow.tables.map(table => table.rows.flatten().flatten()).flatten())
  for paragraph in all.copy() {
    for span in paragraph.spans {
      if span.drawing is Some({ content: @layout.TextBox(_, text), .. }) {
        all.append(text.paragraphs())
      }
    }
  }
  let models = Map::from_array(all.map(p => (p.id, p)))
  let output = StringBuilder()
  output.write_string("<od:body xmlns:od=\"\{word_uri}\">")
  output.write_string(numbering)
  let mut units = numbering.length() + 80
  let siblings = tree.children[tree.nodes[range.start.paragraph].parent]
  let blocks = siblings[siblings.search(range.start.paragraph).unwrap():siblings
    .search(range.end.paragraph)
    .unwrap() +
    1]
  for paragraph in blocks {
    if tree.nodes[paragraph].name == "tbl" {
      let model = flow.tables
        .iter()
        .find_first(table => table.id == paragraph)
        .unwrap()
      let grid = self.check_fragment_table(tree, model, notes=true)
      let markup = self.capture_table_fragment(
        tree,
        grid,
        0,
        grid.rows.length(),
        0,
        model.widths.length(),
        grid.cells.flatten(),
        fields,
        numbers~,
        markers~,
        body=true,
      )
      guard markup.length() <= limit - units else {
        @failure.reject(
          "limit-exceeded", "Rich document fragment exceeds source budget",
        )
      }
      units += markup.length()
      output.write_string(markup)
      continue
    }
    let texts = self.editable_texts(paragraph, notes=true)
    let length = texts.fold(init=0, (sum, node) => {
      sum + inline_text(tree.nodes[node.id]).length()
    })
    let start = if paragraph == range.start.paragraph {
      range.start.offset
    } else {
      0
    }
    let end = if paragraph == range.end.paragraph {
      range.end.offset
    } else {
      length
    }
    let pictures : Map[Int32, String] = Map([])
    for text in texts; offset = 0 {
      let count = inline_text(tree.nodes[text.id]).length()
      if tree.nodes[text.id].name == "drawing" &&
        offset >= start &&
        offset < end {
        pictures[text.id] = self.fragment_drawing(tree, text.id, limit)
      } else if note_reference(tree.nodes[text.id]) &&
        offset >= start &&
        offset < end {
        pictures[text.id] = self.fragment_note(tree, text.id, limit)
      }
      continue offset + count
    }
    let markup = fragment_paragraph(
      tree,
      models[paragraph],
      styles,
      document,
      limit,
      links,
      bookmarks,
      markers,
      numbers,
      pictures,
      fields~,
      start~,
      end~,
    )
    let bindings = tree.namespace_bindings(paragraph)
    bindings["od"] = word_uri
    let opening = "<od:p" +
      bindings
      .keys()
      .to_array()
      .map(prefix => {
        let name = if prefix.is_empty() { "xmlns" } else { "xmlns:" + prefix }
        " " + name + "=\"" + property_attribute(bindings[prefix]) + "\""
      })
      .join("") +
      ">"
    let markup = markup.replace(old="<od:p>", new=opening)
    guard markup.length() <= limit - units else {
      @failure.reject(
        "limit-exceeded", "Rich document fragment exceeds source budget",
      )
    }
    units += markup.length()
    output.write_string(markup)
  }
  output.write_string("</od:body>")
  self.fragment_citation_sources(output.to_string(), limit)
}

///|
/// Captures an editable text range with portable formatting and resources.
/// Supply the current layout when the selected range contains page fields.
pub fn Session::clipboard(
  self : Session,
  revision : Int32,
  selection : Selection,
  cut~ : Bool = false,
  layout? : @layout.Layout,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let tree = WordTree::new(self.document())
  if self.table_cell_range(
      tree,
      selection,
      pictures=true,
      fields=true,
      math=true,
      notes=true,
    )
    is Some(_) {
    return self.table_clipboard(revision, selection, cut~, layout?)
  }
  let text = self.selected_text(revision, selection, layout?)
  let mut reason = ""
  let fragment = Json(self.capture_body_fragment(selection, layout?)) catch {
    @failure.Failure(code="protected-content", message~, ..) => {
      reason = message
      Json::null()
    }
    error => raise error
  }
  if cut {
    if fragment == Json::null() {
      ignore(self.selected_text(revision, selection, cut=true, layout?))
    } else {
      let tree = WordTree::new(self.document())
      let range = self.paragraph_range(
        tree,
        selection,
        structural=true,
        fields=true,
        math=true,
        tables=true,
        notes=true,
      )
      self.check_drawing_range(tree, range)
      if range.paragraphs.any(p => {
          tree.descendants(p).any(id => note_reference(tree.nodes[id]))
        }) {
        if self.prepare_plain_range(selection, "", notes=true) is Some(prepared) {
          ignore(self.note_transition(prepared.document, self.parts))
        }
      }
    }
  }
  {
    "kind": "body",
    "text": text,
    "fragment": fragment,
    "reason": reason,
    "selection": Json(selection),
  }
}
