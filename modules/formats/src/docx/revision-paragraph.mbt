///|
fn WordTree::is_paragraph_revision(self : WordTree, id : Int) -> Bool {
  guard self.nodes.get(id) is Some(node) &&
    node.uri == word_uri &&
    ["ins", "del"].contains(node.name) &&
    self.nodes.get(node.parent) is Some(run) &&
    run.uri == word_uri &&
    run.name == "rPr" &&
    self.nodes.get(run.parent) is Some(properties) &&
    properties.uri == word_uri &&
    properties.name == "pPr" &&
    self.nodes.get(properties.parent) is Some(paragraph) else {
    return false
  }
  paragraph.uri == word_uri && paragraph.name == "p"
}

///|
fn WordTree::paragraph_revision(self : WordTree, paragraph : Int) -> Int? {
  self
  .child(paragraph, "pPr")
  .bind(id => self.child(id, "rPr"))
  .bind(id => {
    self.children[id]
    .iter()
    .find_first(child => self.is_paragraph_revision(child))
  })
}

///|
fn WordTree::check_paragraph_revision(
  self : WordTree,
  id : Int,
) -> Int raise @failure.Failure {
  guard self.is_paragraph_revision(id) else {
    @failure.reject("protected-content", "Invalid paragraph revision parent")
  }
  let node = self.nodes[id]
  let paragraph = self.nodes[self.nodes[node.parent].parent].parent
  self.check_revision_paragraph(paragraph)
  let source = self.source[node.start:node.end]
  guard self.children[id].is_empty() &&
    node.text.trim().is_empty() &&
    node.attributes.all(a => {
      a.uri == word_uri && ["id", "author", "date"].contains(a.name)
    }) &&
    !source.contains("<!--") &&
    !source.contains("<?") &&
    self.children[node.parent]
    .filter(child => self.is_paragraph_revision(child))
    .length() ==
    1 else {
    @failure.reject(
      "protected-content", "Unknown or conflicting paragraph mark revision",
    )
  }
  ignore(comment_key(node.attribute("id", uri=word_uri).unwrap_or("")))
  ignore(self.revision_next_paragraph(paragraph))
  paragraph
}

///|
fn WordTree::revision_next_paragraph(
  self : WordTree,
  paragraph : Int,
) -> Int raise @failure.Failure {
  let siblings = self.children[self.nodes[paragraph].parent]
  let index = siblings.search(paragraph).unwrap()
  guard siblings.get(index + 1) is Some(next) &&
    self.nodes[next].uri == word_uri &&
    self.nodes[next].name == "p" else {
    @failure.reject(
      "protected-content", "Paragraph mark crosses a protected boundary",
    )
  }
  next
}

///|
fn WordTree::paragraph_revision_properties(
  self : WordTree,
  id : Int,
) -> Array[Int] raise @failure.Failure {
  let run = if self.nodes[id].name == "pPr" {
    self.child(id, "rPr")
  } else if self.nodes[id].name == "rPr" &&
    self.nodes.get(self.nodes[id].parent).map(node => node.name) == Some("pPr") {
    Some(id)
  } else {
    None
  }
  let marks = run
    .map(id => {
      self.children[id].filter(child => self.is_paragraph_revision(child))
    })
    .unwrap_or([])
  for mark in marks {
    ignore(self.check_paragraph_revision(mark))
  }
  marks
}

///|
fn paragraph_revision_properties(
  tree : WordTree,
  document : @xml.Document,
  paragraph : Int,
  markup : String,
) -> String raise @failure.Failure {
  let run = tree
    .child(paragraph, "pPr")
    .map(properties => {
      formatted_properties(tree, document, properties, "rPr", Map([]), nested={
        "ins": "",
        "del": markup,
      })
    })
    .unwrap_or("<od:rPr xmlns:od=\"\{word_uri}\">\{markup}</od:rPr>")
  formatted_properties(tree, document, paragraph, "pPr", Map([]), nested={
    "rPr": run,
  })
}

///|
fn Session::merge_review_paragraphs(
  self : Session,
  document : @xml.Document,
  first : Int,
) -> (@xml.Document, @xml.Edit, Int) raise @failure.Failure {
  let tree = WordTree::new(document)
  let last = tree.revision_next_paragraph(first)
  ignore(tree.review_text_parts(first))
  let parts = tree.review_text_parts(last)
  guard tree.child(last, "pPr").bind(id => tree.child(id, "pPrChange")) is None &&
    tree
    .child(first, "pPr")
    .bind(id => tree.child(id, "rPr"))
    .bind(id => tree.child(id, "rPrChange"))
    is None else {
    @failure.reject(
      "protected-content", "Review paragraph properties before merging this boundary",
    )
  }
  let left = tree.nodes[first]
  let right = tree.nodes[last]
  guard document.source()[left.end:right.start].trim().is_empty() else {
    @failure.reject(
      "protected-content", "Retained interparagraph markup prevents merging",
    )
  }
  let mark = tree
    .child(last, "pPr")
    .bind(id => tree.child(id, "rPr"))
    .map(id => tree.standalone_markup(document, id))
    .unwrap_or("")
  let properties = formatted_properties(tree, document, first, "pPr", Map([]), nested={
    "rPr": mark,
  })
  let changes : Array[@xml.SourceChange] = []
  if properties_change(tree, document, first, "pPr", properties) is Some(change) {
    changes.push(change)
  }
  if right.empty {
    changes.push({
      node: right.parent,
      offset: right.start - tree.nodes[right.parent].start,
      length: right.end - right.start,
      xml: "",
    })
  } else {
    changes.push({
      node: left.parent,
      offset: left.closing_start - tree.nodes[left.parent].start,
      length: left.end - left.closing_start,
      xml: "",
    })
    changes.push({
      node: right.parent,
      offset: right.start - tree.nodes[right.parent].start,
      length: right.opening_end - right.start,
      xml: "",
    })
    if tree.child(last, "pPr") is Some(properties) {
      let node = tree.nodes[properties]
      changes.push({
        node: right.parent,
        offset: node.start - tree.nodes[right.parent].start,
        length: node.end - node.start,
        xml: "",
      })
    }
    changes.push({
      node: right.parent,
      offset: right.closing_start - tree.nodes[right.parent].start,
      length: right.end - right.closing_start,
      xml: "</\{left.qualified}>",
    })
    for child in tree.children[last].filter(id => tree.nodes[id].name != "pPr") {
      let node = tree.nodes[child]
      let additions = tree.namespace_additions(child, first)
      if !additions.is_empty() {
        changes.push({
          node: child,
          offset: node.opening_end -
          node.start -
          (if node.empty { 2 } else { 1 }),
          length: 0,
          xml: additions,
        })
      }
    }
    let styles = self.styles([])
    for part in parts {
      if self.preserve_run_style(tree, styles, part.run, first) is Some(change) {
        changes.push(change)
      }
    }
  }
  let (candidate, edit) = document.edit_source(changes)
  (candidate, edit, last)
}
