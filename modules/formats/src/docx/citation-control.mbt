///|
fn WordTree::citation_content(
  self : WordTree,
  id : Int32,
) -> Int32 raise @failure.Failure {
  let node = self.nodes[id]
  guard node.uri == word_uri &&
    node.name == "sdt" &&
    node.attributes.is_empty() &&
    node.text.trim().is_empty() &&
    node.parent >= 0 &&
    self.nodes[node.parent].uri == word_uri &&
    self.nodes[node.parent].name == "p" &&
    self.children[id].all(child => {
      self.nodes[child].uri == word_uri &&
      ["sdtPr", "sdtEndPr", "sdtContent"].contains(self.nodes[child].name)
    }) &&
    self.children[id].filter(child => self.nodes[child].name == "sdtPr")
    is [properties] &&
    self.children[id].filter(child => self.nodes[child].name == "sdtContent")
    is [content] &&
    self.children[id]
    .filter(child => self.nodes[child].name == "sdtEndPr")
    .length() <=
    1 else {
    @failure.reject("protected-content", "Extended citation content control")
  }
  guard self.nodes[properties].attributes.is_empty() &&
    self.nodes[properties].text.trim().is_empty() &&
    self.children[properties].filter(child => {
      self.nodes[child].name == "citation"
    })
    is [citation] &&
    self.children[properties]
    .filter(child => self.nodes[child].name == "id")
    .length() <=
    1 else {
    @failure.reject("protected-content", "Invalid citation control properties")
  }
  for child in self.children[properties] {
    let item = self.nodes[child]
    guard item.uri == word_uri &&
      ["id", "citation"].contains(item.name) &&
      self.children[child].is_empty() &&
      item.text.trim().is_empty() else {
      @failure.reject("protected-content", "Extended citation control property")
    }
    if child == citation {
      guard item.attributes.is_empty() else {
        @failure.reject("protected-content", "Extended citation control type")
      }
    } else {
      guard item.attributes.length() == 1 &&
        item.attributes[0].uri == word_uri &&
        item.attributes[0].name == "val" else {
        @failure.reject(
          "protected-content", "Invalid citation control identity",
        )
      }
      ignore(@string.parse_int(item.attributes[0].value[:])) catch {
        _ =>
          @failure.reject(
            "protected-content", "Invalid citation control identity",
          )
      }
    }
  }
  if self.child(id, "sdtEndPr") is Some(ending) {
    guard self.nodes[ending].attributes.is_empty() &&
      self.nodes[ending].text.trim().is_empty() &&
      self.children[ending].is_empty() else {
      @failure.reject(
        "protected-content", "Extended citation ending properties",
      )
    }
  }
  guard self.nodes[content].attributes.is_empty() &&
    self.nodes[content].text.trim().is_empty() &&
    self.children[content].all(child => {
      self.nodes[child].uri == word_uri && self.nodes[child].name == "r"
    }) else {
    @failure.reject("protected-content", "Extended citation control contents")
  }
  content
}
