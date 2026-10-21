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
  let selected : Map[Int, Bool] = Map([])
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
  let models = Map::from_array(all.map(p => (p.id, p)))
  let output = StringBuilder()
  output.write_string("<od:body xmlns:od=\"\{word_uri}\">")
  output.write_string(numbering)
  let mut units = numbering.length() + 80
  for paragraph in range.paragraphs {
    let texts = self.editable_texts(paragraph)
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
    let pictures : Map[Int, String] = Map([])
    for text in texts; offset = 0 {
      let count = inline_text(tree.nodes[text.id]).length()
      if tree.nodes[text.id].name == "drawing" &&
        offset >= start &&
        offset < end {
        pictures[text.id] = self.fragment_picture(tree, text.id, limit)
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
  output.to_string()
}

///|
/// Captures an editable text range with portable formatting and resources.
/// Supply the current layout when the selected range contains page fields.
pub fn Session::clipboard(
  self : Session,
  revision : Int,
  selection : Selection,
  cut~ : Bool = false,
  layout? : @layout.Layout,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let tree = WordTree::new(self.document())
  if self.table_cell_range(tree, selection, pictures=true, fields=true)
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
      self.check_picture_range(
        tree,
        self.paragraph_range(tree, selection, structural=true, fields=true),
      )
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
