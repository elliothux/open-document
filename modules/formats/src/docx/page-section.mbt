///|
fn WordTree::page_sections(
  self : WordTree,
) -> Array[Int?] raise @failure.Failure {
  let body = self.child(0, "body").unwrap()
  let sections : Array[Int?] = []
  for id in self.children[body] {
    let node = self.nodes[id]
    if node.uri != word_uri {
      continue
    }
    if node.name == "sectPr" {
      guard self.children[body].last() == Some(id) else {
        @failure.reject(
          "protected-content", "Section properties must end the document body",
        )
      }
      sections.push(Some(id))
    } else if node.name == "p" {
      if self.child(id, "pPr") is Some(properties) {
        let ends = self.children[properties].filter(child => {
          self.nodes[child].uri == word_uri &&
          self.nodes[child].name == "sectPr"
        })
        guard ends.length() <= 1 else {
          @failure.reject(
            "protected-content", "Duplicate paragraph section properties",
          )
        }
        if ends is [id] {
          sections.push(Some(id))
        }
      }
    }
  }
  let native_count = self.order
    .filter(id => {
      self.nodes[id].uri == word_uri && self.nodes[id].name == "sectPr"
    })
    .length()
  guard sections.length() == native_count else {
    @failure.reject(
      "protected-content", "Section properties are inside a protected container",
    )
  }
  if self.children[body]
    .last()
    .map(id => self.nodes[id].uri == word_uri && self.nodes[id].name == "sectPr") !=
    Some(true) {
    sections.push(None)
  }
  guard sections.length() <= 1024 else {
    @failure.reject("limit-exceeded", "Section count exceeds page budget")
  }
  sections
}

///|
fn page_section(
  document : @xml.Document,
  tree : WordTree,
  section : Int?,
) -> (@xml.Document, Array[@xml.Edit], Int) raise @failure.Failure {
  if section is Some(id) {
    return (document, [], id)
  }
  let body = tree.child(0, "body").unwrap()
  let node = tree.nodes[body]
  let markup = "<od:sectPr xmlns:od=\"\{word_uri}\"/>"
  let change : @xml.SourceChange = if node.empty {
    {
      node: body,
      offset: node.opening_end - node.start - 2,
      length: 2,
      xml: ">\{markup}</\{node.qualified}>",
    }
  } else {
    {
      node: body,
      offset: node.closing_start - node.start,
      length: 0,
      xml: markup,
    }
  }
  let (candidate, edit) = document.edit_source([change])
  (candidate, [edit], WordTree::new(candidate).child(body, "sectPr").unwrap())
}
