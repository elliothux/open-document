///|
fn WordTree::page_sections(
  self : WordTree,
) -> Array[Int32?] raise @failure.Failure {
  let body = self.child(0, "body").unwrap()
  let sections : Array[Int32?] = []
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
  section : Int32?,
) -> (@xml.Document, Array[@xml.Edit], Int32) raise @failure.Failure {
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

///|
fn WordTree::section_start_type(
  self : WordTree,
  section : Int32?,
) -> String raise @failure.Failure {
  let kinds = section
    .map(id => {
      self.children[id].filter(child => {
        self.nodes[child].uri == word_uri && self.nodes[child].name == "type"
      })
    })
    .unwrap_or([])
  guard kinds.length() <= 1 else {
    @failure.reject("protected-content", "Duplicate section start type")
  }
  let kind = kinds
    .get(0)
    .bind(id => self.nodes[id].attribute("val", uri=word_uri))
    .unwrap_or("nextPage")
  guard ["nextPage", "oddPage", "evenPage", "continuous"].contains(kind) else {
    @failure.reject("protected-content", "Unsupported section start type")
  }
  kind
}

///|
fn WordTree::section_start_change(
  self : WordTree,
  document : @xml.Document,
  section : Int32,
  kind : String,
) -> @xml.SourceChange? raise @failure.Failure {
  ignore(self.section_start_type(Some(section)))
  let markup = "<od:type xmlns:od='\{word_uri}' od:val='\{kind}'/>"
  if self.child(section, "type") is Some(id) {
    let node = self.nodes[id]
    let source = document.source()[node.start:node.end]
    guard !source.contains("<!--") &&
      !source.contains("<?") &&
      self.children[id].is_empty() &&
      node.text.trim().is_empty() &&
      node.attributes.all(a => a.uri == word_uri && a.name == "val") else {
      @failure.reject(
        "protected-content", "Extended section start type is protected",
      )
    }
    return properties_change(self, document, section, "type", markup)
  }
  let node = self.nodes[section]
  let previous = self.children[section]
    .filter(id => {
      ["headerReference", "footerReference", "footnotePr", "endnotePr"].contains(
        self.nodes[id].name,
      )
    })
    .last()
  Some(
    if node.empty {
      section_insertion(self, section, markup)
    } else {
      {
        node: section,
        offset: previous
        .map(id => self.nodes[id].end)
        .unwrap_or(node.opening_end) -
        node.start,
        length: 0,
        xml: markup,
      }
    },
  )
}
