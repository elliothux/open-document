///|
fn WordTree::check_revision_paragraph(
  self : WordTree,
  paragraph : Int32,
) -> Unit raise @failure.Failure {
  let parent = self.nodes[self.nodes[paragraph].parent]
  let body = if parent.name == "body" && parent.uri == word_uri {
    parent.id
  } else if parent.name == "tc" &&
    parent.uri == word_uri &&
    self.nodes.get(parent.parent) is Some(row) &&
    row.name == "tr" &&
    row.uri == word_uri &&
    self.nodes.get(row.parent) is Some(table) &&
    table.name == "tbl" &&
    table.uri == word_uri {
    table.parent
  } else {
    -1
  }
  guard self.nodes.get(body) is Some(body) &&
    body.name == "body" &&
    body.uri == word_uri &&
    body.parent == 0 else {
    @failure.reject(
      "protected-content", "Revision is inside a protected content region",
    )
  }
}

///|
fn WordTree::check_property_revision(
  self : WordTree,
  id : Int32,
) -> Int32 raise @failure.Failure {
  let change = self.nodes[id]
  guard change.uri == word_uri &&
    ["rPrChange", "pPrChange"].contains(change.name) &&
    change.attributes.all(a => {
      a.uri == word_uri && ["id", "author", "date"].contains(a.name)
    }) &&
    change.text.trim().is_empty() &&
    self.nodes.get(change.parent) is Some(properties) &&
    properties.uri == word_uri &&
    change.name == properties.name + "Change" &&
    self.children[id] is [previous] &&
    self.nodes[previous].uri == word_uri &&
    self.nodes[previous].name == properties.name else {
    @failure.reject(
      "protected-content", "Property revision requires one matching previous property set",
    )
  }
  ignore(comment_key(change.attribute("id", uri=word_uri).unwrap_or("")))
  let owner = self.nodes[properties.parent]
  let paragraph = if properties.name == "pPr" &&
    owner.name == "p" &&
    owner.uri == word_uri {
    owner.id
  } else if properties.name == "rPr" &&
    owner.name == "pPr" &&
    owner.uri == word_uri {
    owner.parent
  } else if properties.name == "rPr" &&
    owner.name == "r" &&
    owner.uri == word_uri {
    let parent = self.nodes[owner.parent]
    if parent.uri == word_uri && ["ins", "del"].contains(parent.name) {
      parent.parent
    } else {
      owner.parent
    }
  } else {
    -1
  }
  guard self.nodes.get(paragraph) is Some(p) &&
    p.name == "p" &&
    p.uri == word_uri &&
    self.children[properties.parent]
    .filter(child => {
      self.nodes[child].uri == word_uri &&
      self.nodes[child].name == properties.name
    })
    .length() ==
    1 else {
    @failure.reject(
      "protected-content", "Property revision requires ordinary paragraph or run properties",
    )
  }
  self.check_revision_paragraph(paragraph)
  let fragment = self.source[properties.start:properties.end]
  guard properties.attributes.is_empty() &&
    !fragment.contains("<!--") &&
    !fragment.contains("<?") else {
    @failure.reject(
      "protected-content", "Opaque property revision source is protected",
    )
  }
  self.check_structure_properties(previous)
  guard properties.name != "pPr" || self.child(previous, "rPr") is None else {
    @failure.reject(
      "protected-content", "Previous paragraph properties cannot contain paragraph-mark formatting",
    )
  }
  let excluded = [id]
  if properties.name == "pPr" &&
    self.child(properties.id, "rPr").bind(id => self.child(id, "rPrChange"))
    is Some(mark) {
    ignore(self.check_property_revision(mark))
    excluded.push(mark)
  }
  self.check_current_review_properties(properties.id, excluded)
  paragraph
}

///|
fn WordTree::check_current_review_properties(
  self : WordTree,
  id : Int32,
  excluded : Array[Int32],
) -> Unit raise @failure.Failure {
  let properties = self.nodes[id]
  let fragment = self.source[properties.start:properties.end]
  guard properties.attributes.is_empty() &&
    !fragment.contains("<!--") &&
    !fragment.contains("<?") else {
    @failure.reject(
      "protected-content", "Opaque current property source is protected",
    )
  }
  let excluded = excluded + self.paragraph_revision_properties(id)
  // Validate current properties with independently checked revision metadata removed.
  let opening = StringBuilder()
  opening.write_string("<" + properties.qualified)
  for prefix, uri in self.namespace_bindings(properties.id) {
    let name = if prefix.is_empty() { "xmlns" } else { "xmlns:" + prefix }
    opening.write_string(" \{name}=\"" + property_attribute(uri) + "\"")
  }
  opening.write_string(">")
  let mut cursor = properties.opening_end
  for id in self.order {
    if excluded.contains(id) {
      let change = self.nodes[id]
      opening.write_string(self.source[cursor:change.start].to_owned())
      cursor = change.end
    }
  }
  opening.write_string(self.source[cursor:properties.closing_start].to_owned())
  opening.write_string("</" + properties.qualified + ">")
  let bytes = @utf8.encode(opening.to_string())
  let current = WordTree::new(
    @xml.Document::parse(bytes, "revision-properties", 128, bytes.length()),
  )
  current.check_structure_properties(0)
}

///|
fn property_revision_change(
  document : @xml.Document,
  tree : WordTree,
  id : Int32,
  accept : Bool,
) -> @xml.SourceChange raise @failure.Failure {
  let change = tree.nodes[id]
  let properties = tree.nodes[change.parent]
  if accept {
    return {
      node: properties.id,
      offset: change.start - properties.start,
      length: change.end - change.start,
      xml: "",
    }
  }
  let parent = tree.nodes[properties.parent]
  let previous = tree.nodes[tree.children[id][0]]
  let mut markup = tree.standalone_markup(document, previous.id)
  if properties.name == "pPr" && tree.child(properties.id, "rPr") is Some(mark) {
    // Paragraph-mark formatting is outside the previous paragraph property set.
    let retained = tree.standalone_markup(document, mark)
    let tail = if previous.empty {
      2
    } else {
      previous.end - previous.closing_start
    }
    markup = markup[:markup.length() - tail].to_owned() +
      (if previous.empty { ">" } else { "" }) +
      retained +
      "</" +
      previous.qualified +
      ">"
  }
  if properties.name == "rPr" && parent.name == "pPr" {
    let retained = tree
      .paragraph_revision_properties(properties.id)
      .map(id => tree.standalone_markup(document, id))
      .join("")
    if !retained.is_empty() {
      let tail = if previous.empty {
        2
      } else {
        previous.end - previous.closing_start
      }
      markup = markup[:markup.length() - tail].to_owned() +
        (if previous.empty { ">" } else { "" }) +
        retained +
        "</\{previous.qualified}>"
    }
  }
  if properties.name == "trPr" {
    let retained = tree.children[properties.id]
      .filter(id => tree.is_row_revision(id))
      .map(id => tree.standalone_markup(document, id))
      .join("")
    if !retained.is_empty() {
      let tail = if previous.empty {
        2
      } else {
        previous.end - previous.closing_start
      }
      markup = markup[:markup.length() - tail].to_owned() +
        (if previous.empty { ">" } else { "" }) +
        retained +
        "</\{previous.qualified}>"
    }
  }
  {
    node: parent.id,
    offset: properties.start - parent.start,
    length: properties.end - properties.start,
    xml: markup,
  }
}
