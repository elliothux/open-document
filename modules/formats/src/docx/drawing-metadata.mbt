///|
fn WordTree::disabled_picture_dpi(self : WordTree, id : Int32) -> Bool {
  guard self.children[id] is [list] &&
    self.children[list] is [extension] &&
    self.children[extension] is [dpi] &&
    self.children[dpi].is_empty() else {
    return false
  }
  let list = self.nodes[list]
  let extension = self.nodes[extension]
  let dpi = self.nodes[dpi]
  list.uri == picture_drawing_uri &&
  list.name == "extLst" &&
  list.attributes.is_empty() &&
  list.text.trim().is_empty() &&
  extension.uri == picture_drawing_uri &&
  extension.name == "ext" &&
  extension.attributes.length() == 1 &&
  extension.attribute("uri").map(value => value.to_upper()) ==
  Some("{28A0092B-C50C-407E-A947-70E740481C1C}") &&
  extension.text.trim().is_empty() &&
  dpi.uri == "http://schemas.microsoft.com/office/drawing/2010/main" &&
  dpi.name == "useLocalDpi" &&
  dpi.attributes.length() == 1 &&
  (dpi.attribute("val") == Some("0") || dpi.attribute("val") == Some("false")) &&
  dpi.text.trim().is_empty()
}

///|
fn WordTree::zero_relative_size(
  self : WordTree,
  id : Int32,
) -> Unit raise @failure.Failure {
  let node = self.nodes[id]
  let horizontal = node.name == "sizeRelH"
  let references = if horizontal {
    [
      "page", "margin", "leftMargin", "rightMargin", "insideMargin", "outsideMargin",
    ]
  } else {
    [
      "page", "margin", "topMargin", "bottomMargin", "insideMargin", "outsideMargin",
    ]
  }
  guard node.text.trim().is_empty() &&
    node.attributes.length() == 1 &&
    node.attributes.all(a => {
      a.uri.is_empty() &&
      a.name == "relativeFrom" &&
      references.contains(a.value)
    }) &&
    self.children[id] is [percent] &&
    self.nodes[percent].uri == drawing_2010_uri &&
    self.nodes[percent].name ==
    (if horizontal { "pctWidth" } else { "pctHeight" }) &&
    self.nodes[percent].attributes.is_empty() &&
    self.children[percent].is_empty() &&
    self.nodes[percent].text.trim() == "0" else {
    @failure.reject(
      "unsupported-layout", "Relative drawing dimensions require support",
    )
  }
}

///|
// Hidden paint stores inactive colors for later editing.
fn WordTree::hidden_shape_paint(
  self : WordTree,
  id : Int32,
) -> Unit raise @failure.Failure {
  guard self.nodes[id].attributes.is_empty() &&
    self.nodes[id].text.trim().is_empty() &&
    self.children[id].all(child => {
      self.nodes[child].uri == picture_drawing_uri &&
      self.nodes[child].name == "ext"
    }) else {
    @failure.reject("unsupported-layout", "Unknown shape extension attributes")
  }
  let seen : Set[String] = Set([])
  for extension in self.children[id] {
    let node = self.nodes[extension]
    let uri = node.attribute("uri").unwrap_or("").to_upper()
    let fill = uri == "{909E8E84-426E-40DD-AFC4-6F175D3DCCD1}"
    guard !seen.contains(uri) &&
      node.text.trim().is_empty() &&
      node.attributes.length() == 1 &&
      node.attributes.all(a => a.uri.is_empty() && a.name == "uri") &&
      (fill || uri == "{91240B29-F687-4F45-9708-019B960494DF}") &&
      self.children[extension] is [paint] &&
      self.nodes[paint].uri ==
      "http://schemas.microsoft.com/office/drawing/2010/main" &&
      self.nodes[paint].name == (if fill { "hiddenFill" } else { "hiddenLine" }) else {
      @failure.reject("unsupported-layout", "Unknown shape paint extension")
    }
    seen.add(uri)
    guard self.nodes[paint].attributes.all(a => {
      !fill && a.uri.is_empty() && a.name == "w"
    }) else {
      @failure.reject(
        "unsupported-layout", "Unknown hidden shape paint attributes",
      )
    }
    if self.nodes[paint].attribute("w") is Some(_) {
      ignore(drawing_number(self.nodes[paint], "w"))
    }
    self.shape_children(
      paint,
      if fill {
        ["solidFill", "noFill"]
      } else {
        ["solidFill", "noFill", "miter", "headEnd", "tailEnd"]
      },
    )
    ignore(self.shape_rgb(paint))
    for child in self.children[paint] {
      let metadata = self.nodes[child]
      if ["solidFill", "noFill"].contains(metadata.name) {
        continue
      }
      self.shape_children(child, [])
      guard metadata.attributes.all(a => {
        a.uri.is_empty() &&
        (if metadata.name == "miter" {
          a.name == "lim" &&
          (@string.parse_int(a.value[:]) catch { _ => -1 }) >= 0
        } else {
          a.name == "type" && a.value == "none"
        })
      }) else {
        @failure.reject(
          "unsupported-layout", "Unknown hidden shape line metadata",
        )
      }
    }
  }
}
