///|
fn WordTree::check_review_properties(
  self : WordTree,
  id : Int,
) -> Unit raise @failure.Failure {
  let mark = if self.nodes[id].name == "pPr" {
    self.child(id, "rPr").bind(id => self.child(id, "rPrChange"))
  } else {
    None
  }
  if self.child(id, self.nodes[id].name + "Change") is Some(change) {
    ignore(self.check_property_revision(change))
  } else if mark is Some(change) {
    ignore(self.check_property_revision(change))
    self.check_current_review_properties(id, [change])
  } else {
    self.check_structure_properties(id)
  }
}

///|
fn Session::review_format_range(
  self : Session,
  document : @xml.Document,
  selection : Selection,
) -> ParagraphRange raise @failure.Failure {
  self.check_position_in(document, selection.anchor)
  self.check_position_in(document, selection.focus)
  let tree = WordTree::new(document)
  let range = self
    .table_format_range(tree, selection, review=true)
    .unwrap_or_else(() => {
      self.paragraph_range_in(
        document,
        tree,
        selection,
        structural=true,
        tables=true,
        check_layout=false,
        review=true,
      )
    })
  for paragraph in range.paragraphs {
    ignore(tree.review_text_parts(paragraph))
  }
  for p in self.formatting_paragraphs(document, range.paragraphs) {
    guard p.readOnlyReason.is_empty() else {
      @failure.reject("protected-content", p.readOnlyReason)
    }
  }
  range
}

///|
fn WordTree::review_format_ids(self : WordTree) -> Set[String] {
  let ids : Set[String] = Set([])
  for node in self.nodes.values() {
    if node.uri == word_uri && revision_element(node.name) {
      if node.attribute("id", uri=word_uri) is Some(id) {
        ids.add(id)
      }
    }
  }
  ids
}

///|
fn Session::review_format_properties(
  self : Session,
  tree : WordTree,
  document : @xml.Document,
  parent : Int,
  kind : String,
  patch : Map[String, Map[String, String?]?],
  ids : Set[String],
  nested~ : Map[String, String] = Map([]),
) -> String raise @failure.Failure {
  let markup = formatted_properties(
    tree,
    document,
    parent,
    kind,
    patch,
    nested~,
  )
  guard self.tracking_context is Some((author, date)) else { return markup }
  let properties = tree.child(parent, kind)
  let original = properties
    .map(id => {
      let node = tree.nodes[id]
      document.source()[node.start:node.end].to_owned()
    })
    .unwrap_or("")
  if markup == original {
    return markup
  }
  let owner = tree.nodes[tree.nodes[parent].parent]
  if kind == "rPr" && owner.uri == word_uri && owner.name == "ins" {
    guard owner.attribute("author", uri=word_uri) == Some(author) else {
      @failure.reject(
        "protected-content", "Formatting another author's insertion requires review support",
      )
    }
    return markup
  }
  revision_author(author, date)
  let name = kind + "Change"
  let existing = properties.bind(id => tree.child(id, name))
  let id = if existing is Some(id) {
    tree.nodes[id].attribute("id", uri=word_uri).unwrap()
  } else {
    let id = for value in 0..<16384 {
      let key = value.to_string()
      if !ids.contains(key) {
        break key
      }
    } nobreak {
      @failure.reject("limit-exceeded", "Revision identities exhausted")
    }
    ids.add(id)
    id
  }
  let previous = if existing is Some(id) {
    tree.standalone_markup(document, tree.children[id][0])
  } else {
    let content = properties
      .map(id => {
        tree.children[id]
        .filter(
          // Paragraph-mark properties are outside the paragraph property snapshot.
          child => kind != "pPr" || tree.nodes[child].name != "rPr",
        )
        .map(child => tree.standalone_markup(document, child))
        .join("")
      })
      .unwrap_or("")
    "<od:\{kind} xmlns:od=\"\{word_uri}\">\{content}</od:\{kind}>"
  }
  let changes = nested.copy()
  changes[name] = "<od:\{name} xmlns:od=\"\{word_uri}\" od:id=\"\{id}\" od:author=\"" +
    property_attribute(author) +
    "\" od:date=\"" +
    property_attribute(date) +
    "\">" +
    previous +
    "</od:\{name}>"
  formatted_properties(tree, document, parent, kind, patch, nested=changes)
}
