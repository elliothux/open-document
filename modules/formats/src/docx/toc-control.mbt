///|
fn WordTree::toc_control(
  self : WordTree,
  content : Int,
  paragraphs : Array[Int],
  galleryName~ : String = "Table of Contents",
) -> Int raise @failure.Failure {
  let node = self.nodes[content]
  let control = self.nodes.get(node.parent)
  guard node.uri == word_uri &&
    node.name == "sdtContent" &&
    control is Some(control) &&
    control.uri == word_uri &&
    control.name == "sdt" &&
    self.nodes[control.parent].name == "body" &&
    self.nodes[control.parent].uri == word_uri else {
    @failure.reject(
      "protected-content", "Table of contents requires the main body or its native content control",
    )
  }
  guard self.children[control.id].all(id => {
      self.nodes[id].uri == word_uri &&
      ["sdtPr", "sdtEndPr", "sdtContent"].contains(self.nodes[id].name)
    }) &&
    self.children[control.id].filter(id => self.nodes[id].name == "sdtContent") ==
    [content] &&
    self.children[control.id].filter(id => self.nodes[id].name == "sdtPr")
    is [properties] &&
    self.children[control.id]
    .filter(id => self.nodes[id].name == "sdtEndPr")
    .length() <=
    1 &&
    control.attributes.is_empty() &&
    control.text.trim().is_empty() &&
    node.attributes.is_empty() &&
    node.text.trim().is_empty() else {
    @failure.reject(
      "protected-content", "Extended table of contents content control",
    )
  }
  let seen : Set[String] = Set([])
  for id in self.children[properties] {
    let item = self.nodes[id]
    guard item.uri == word_uri && !seen.contains(item.name) else {
      @failure.reject(
        "protected-content", "Duplicate or extended table of contents control property",
      )
    }
    seen.add(item.name)
    match item.name {
      "id" | "tag" | "alias" => {
        guard self.children[id].is_empty() &&
          item.text.trim().is_empty() &&
          item.attributes.all(a => a.uri == word_uri && a.name == "val") else {
          @failure.reject(
            "protected-content", "Extended table of contents control identity",
          )
        }
      }
      "docPartObj" => {
        guard item.attributes.is_empty() &&
          item.text.trim().is_empty() &&
          self.children[id].filter(child => {
            self.nodes[child].name == "docPartGallery"
          })
          is [gallery] &&
          self.nodes[gallery].attribute("val", uri=word_uri) ==
          Some(galleryName) else {
          @failure.reject(
            "protected-content", "Expected the native table of contents gallery",
          )
        }
        let names : Set[String] = Set([])
        for child in self.children[id] {
          let value = self.nodes[child]
          guard value.uri == word_uri &&
            ["docPartGallery", "docPartCategory", "docPartUnique"].contains(
              value.name,
            ) &&
            !names.contains(value.name) &&
            self.children[child].is_empty() &&
            value.text.trim().is_empty() &&
            value.attributes.all(a => a.uri == word_uri && a.name == "val") else {
            @failure.reject(
              "protected-content", "Extended table of contents gallery",
            )
          }
          names.add(value.name)
        }
      }
      "lock" => {
        guard self.children[id].is_empty() &&
          item.text.trim().is_empty() &&
          item.attributes.all(a => a.uri == word_uri && a.name == "val") &&
          item.attribute("val", uri=word_uri) == Some("unlocked") else {
          @failure.reject(
            "protected-content", "Locked table of contents content control",
          )
        }
      }
      _ =>
        @failure.reject(
          "protected-content",
          "Unsupported table of contents control property: " + item.name,
        )
    }
  }
  guard seen.contains("docPartObj") &&
    self.nodes[properties].attributes.is_empty() &&
    self.nodes[properties].text.trim().is_empty() else {
    @failure.reject(
      "protected-content", "Expected native table of contents control properties",
    )
  }
  if self.child(control.id, "sdtEndPr") is Some(ending) {
    guard self.nodes[ending].attributes.is_empty() &&
      self.nodes[ending].text.trim().is_empty() &&
      self.children[ending].all(id => {
        self.nodes[id].uri == word_uri && self.nodes[id].name == "rPr"
      }) &&
      self.children[ending].length() <= 1 else {
      @failure.reject(
        "protected-content", "Extended table of contents ending properties",
      )
    }
  }
  let children = self.children[content]
  if children != paragraphs {
    guard children.length() == paragraphs.length() + 1 &&
      children[1:] == paragraphs[:] &&
      self.nodes[children[0]].uri == word_uri &&
      self.nodes[children[0]].name == "p" &&
      (
        galleryName == "Bibliographies" ||
        self.child(children[0], "pPr").bind(id => self.value(id, "pStyle")) ==
        Some("TOCHeading")
      ) else {
      @failure.reject(
        "protected-content", "Table of contents control contains other content",
      )
    }
    let title = children[0]
    self.check_structure_paragraph(title)
    for id in self.children[title] {
      if self.nodes[id].name == "pPr" {
        continue
      }
      guard self.nodes[id].uri == word_uri &&
        self.nodes[id].name == "r" &&
        self.children[id].all(child => {
          self.nodes[child].uri == word_uri &&
          ["t", "rPr"].contains(self.nodes[child].name)
        }) else {
        @failure.reject(
          "protected-content", "Table of contents title contains retained content",
        )
      }
      for child in self.children[id] {
        if self.nodes[child].name == "t" {
          self.check_field_text(child)
        }
      }
    }
  }
  control.id
}
