///|
fn WordTree::paragraph_section(self : WordTree, paragraph : Int) -> Int? {
  self.child(paragraph, "pPr").bind(id => self.child(id, "sectPr"))
}

///|
fn WordTree::paragraph_section_change(
  self : WordTree,
  paragraph : Int,
  markup : String,
) -> @xml.SourceChange {
  if self.child(paragraph, "pPr") is Some(properties) {
    section_insertion(self, properties, markup)
  } else {
    section_insertion(
      self,
      paragraph,
      "<od:pPr xmlns:od='\{word_uri}'>\{markup}</od:pPr>",
      first=true,
    )
  }
}

///|
fn section_insertion(
  tree : WordTree,
  parent : Int,
  markup : String,
  first~ : Bool = false,
) -> @xml.SourceChange {
  let node = tree.nodes[parent]
  if node.empty {
    {
      node: parent,
      offset: node.opening_end - node.start - 2,
      length: 2,
      xml: ">\{markup}</\{node.qualified}>",
    }
  } else {
    {
      node: parent,
      offset: (if first { node.opening_end } else { node.closing_start }) -
      node.start,
      length: 0,
      xml: markup,
    }
  }
}

///|
fn WordTree::section_reference_source(
  self : WordTree,
  document : @xml.Document,
  section : Int?,
) -> String raise @failure.Failure {
  section
  .map(id => {
    self.children[id]
    .filter(child => {
      let node = self.nodes[child]
      node.uri == word_uri &&
      ["headerReference", "footerReference"].contains(node.name)
    })
    .map(child => self.standalone_markup(document, child))
    .join("")
  })
  .unwrap_or("")
}

///|
/// A split moves the section end; a merge keeps the end paragraph's section.
fn section_range_transition(
  original : @xml.Document,
  candidate : @xml.Document,
  range : ParagraphRange,
  target : Int,
) -> (@xml.Document, Array[@xml.Edit]) raise @failure.Failure {
  let tree = WordTree::new(original)
  let first = range.start.paragraph
  let last = range.end.paragraph
  if first == last && target == first {
    return (candidate, [])
  }
  let current = WordTree::new(candidate)
  let changes : Array[@xml.SourceChange] = []
  if current.paragraph_section(first) is Some(id) {
    let node = current.nodes[id]
    let parent = current.nodes[node.parent]
    changes.push({
      node: parent.id,
      offset: node.start - parent.start,
      length: node.end - node.start,
      xml: "",
    })
  }
  if tree.paragraph_section(last) is Some(id) {
    let markup = tree.standalone_markup(original, id)
    changes.push(current.paragraph_section_change(target, markup))
  }
  let edits : Array[@xml.Edit] = []
  let mut document = candidate
  if !changes.is_empty() {
    let (updated, edit) = candidate.edit_source(changes)
    document = updated
    edits.push(edit)
  }
  let removed = range.paragraphs
    .filter(p => p != last)
    .filter_map(p => tree.paragraph_section(p))
  if removed.is_empty() {
    return (document, edits)
  }
  let mut inherited = ""
  let mut kept = 0
  for section in tree.page_sections() {
    let references = tree.section_reference_source(original, section)
    let effective = if references.is_empty() { inherited } else { references }
    if section is Some(id) && removed.contains(id) {
      inherited = effective
      continue
    }
    // ONLYOFFICE carries headers only when the following section has none of its own.
    if references.is_empty() && !inherited.is_empty() {
      let current = WordTree::new(document)
      let (initial, created, section) = page_section(
        document,
        current,
        current.page_sections()[kept],
      )
      edits.append(created)
      let current = WordTree::new(initial)
      let (updated, edit) = initial.edit_source([
        section_insertion(current, section, inherited, first=true),
      ])
      document = updated
      edits.push(edit)
    }
    inherited = ""
    kept += 1
  }
  (document, edits)
}
