///|
fn Session::drawing_identities(
  self : Session,
) -> Map[String, Bool] raise @failure.Failure {
  let documents = [self.document()]
  for rel in self.relationships() {
    if !rel.external &&
      [
        "http://schemas.openxmlformats.org/officeDocument/2006/relationships/header",
        "http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer",
      ].contains(rel.kind) {
      documents.push(self.part_xml(rel.target))
    }
  }
  let used : Map[String, Bool] = Map([])
  for document in documents {
    for node in document.nodes() {
      if node.name == "docPr" || node.name == "cNvPr" {
        if node.attribute("id") is Some(value) {
          used[picture_identity(value)] = true
        }
      }
      if node.uri == picture_inline_uri && node.name == "anchor" {
        for attribute in node.attributes {
          if attribute.uri == drawing_2010_uri &&
            ["anchorId", "editId"].contains(attribute.name) {
            used["wp14:" + attribute.value.to_upper()] = true
          }
        }
      }
    }
  }
  used
}

///|
fn Session::next_drawing_identity(self : Session) -> Int raise @failure.Failure {
  let used = self.drawing_identities()
  for id = 1; id <= 16384; id = id + 1 {
    if !used.contains(id.to_string()) {
      return id
    }
  }
  @failure.reject("limit-exceeded", "Drawing identities exhausted")
}

///|
fn Session::prepare_drawing_insertion(
  self : Session,
  drawing : String,
) -> PreparedEdit raise @failure.Failure {
  guard self.selection is Some(selection) else {
    @failure.reject("invalid-position", "Select a document position first")
  }
  let original = self.document()
  let tree = WordTree::new(original)
  self.check_picture_context(tree)
  let range = self.paragraph_range(tree, selection, structural=true)
  guard tree.order
    .filter(id => {
      tree.nodes[id].uri == word_uri && tree.nodes[id].name == "drawing"
    })
    .length() <
    256 else {
    @failure.reject("limit-exceeded", "Drawing list exceeds 256 entries")
  }
  let prepared = if range.start.paragraph == range.end.paragraph {
    self.prepare_plain_range(selection, "")
  } else {
    Some(self.prepare_structural_range(selection, ""))
  }
  let document = prepared.map(edit => edit.document).unwrap_or(original)
  let position = prepared
    .bind(edit => edit.edit.after)
    .map(value => value.focus)
    .unwrap_or(range.start)
  let xml = prepared.map(edit => edit.edit.xml.copy()).unwrap_or([])
  let paragraphs = prepared
    .map(edit => edit.edit.paragraphs.copy())
    .unwrap_or([position.paragraph])
  let tree = WordTree::new(document)
  let texts = docx_texts(tree).filter(item => {
    item.paragraph == position.paragraph
  })
  let target = for item in texts; offset = 0 {
    let length = inline_text(tree.nodes[item.id]).length()
    if position.offset < offset + length ||
      (position.offset == offset + length && position.affinity == "before") {
      break Some((item.id, position.offset - offset))
    }
    continue offset + length
  } nobreak {
    texts
    .last()
    .map(item => (item.id, inline_text(tree.nodes[item.id]).length()))
  }
  let limit = self.opc.budget.entry_bytes.min(history_byte_limit / 2)
  let change : @xml.SourceChange = if target is Some((id, offset)) {
    let node = tree.nodes[id]
    guard tree.nodes[node.parent].parent == position.paragraph else {
      @failure.reject(
        "protected-content", "Drawing insertion inside hyperlinks requires editing support",
      )
    }
    if node.name == "drawing" {
      let parent = tree.nodes[node.parent]
      {
        node: parent.id,
        offset: (if offset == 0 { node.start } else { node.end }) - parent.start,
        length: 0,
        xml: drawing,
      }
    } else {
      guard node.attributes.all(attr => {
          (
            node.name == "t" &&
            attr.uri == "http://www.w3.org/XML/1998/namespace" &&
            attr.name == "space"
          ) ||
          (
            node.name == "br" &&
            attr.uri == word_uri &&
            ["type", "clear"].contains(attr.name)
          )
        }) &&
        !document.source()[node.start:node.end].contains("<!--") &&
        !document.source()[node.start:node.end].contains("<?") else {
        @failure.reject(
          "protected-content", "Unknown inline source prevents drawing insertion",
        )
      }
      let text = inline_text(node)
      let markup = inline_markup(text[:offset].to_owned(), limit) +
        drawing +
        inline_markup(text[offset:].to_owned(), limit)
      guard markup.length() <= limit else {
        @failure.reject(
          "limit-exceeded", "Drawing insertion source exceeds budget",
        )
      }
      let parent = tree.nodes[node.parent]
      {
        node: parent.id,
        offset: node.start - parent.start,
        length: node.end - node.start,
        xml: markup,
      }
    }
  } else {
    let run = tree.child(position.paragraph, "r")
    let parent = tree.nodes[run.unwrap_or(position.paragraph)]
    let markup = if run is Some(_) {
      drawing
    } else {
      "<od:r xmlns:od=\"\{word_uri}\">" +
      tree.empty_run_properties(document, position.paragraph) +
      drawing +
      "</od:r>"
    }
    if parent.empty {
      {
        node: parent.id,
        offset: parent.opening_end - parent.start - 2,
        length: 2,
        xml: ">" + markup + "</" + parent.qualified + ">",
      }
    } else {
      {
        node: parent.id,
        offset: parent.closing_start - parent.start,
        length: 0,
        xml: markup,
      }
    }
  }
  let (candidate, step) = document.edit_source([change])
  xml.push(step)
  let text = docx_texts(WordTree::new(candidate))
    .filter(item => item.paragraph == position.paragraph)
    .map(item => inline_text(candidate.node(item.id)))
    .join("")
  let caret = {
    ..position,
    offset: editing_boundaries(text, true)
    .iter()
    .find_first(value => value >= position.offset + 1)
    .unwrap(),
    affinity: "after",
    bidiLevel: None,
    frameStart: None,
  }
  let mut bytes = 0
  for step in xml {
    let size = edit_bytes(step)
    guard size <= history_byte_limit - bytes else {
      @failure.reject(
        "limit-exceeded", "Drawing insertion exceeds history budget",
      )
    }
    bytes += size
  }
  {
    edit: {
      xml,
      parts: Map([]),
      created: Map([]),
      created_media: Map([]),
      before: self.selection,
      after: Some({ anchor: caret, focus: caret, }),
      paragraphs,
      bytes,
    },
    document: candidate,
    typing_text: None,
    join_group: false,
  }
}
