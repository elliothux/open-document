///|
fn WordTree::shape_polyline(
  self : WordTree,
  geometry : Int32,
) -> Array[(Double, Double)] raise @failure.Failure {
  self.shape_children(geometry, [
    "avLst", "gdLst", "ahLst", "cxnLst", "rect", "pathLst",
  ])
  guard self.nodes[geometry].attributes.is_empty() else {
    @failure.reject("unsupported-layout", "Unknown ink geometry attributes")
  }
  for child in self.children[geometry] {
    let node = self.nodes[child]
    if ["avLst", "gdLst", "ahLst", "cxnLst"].contains(node.name) {
      self.shape_children(child, [])
      guard node.attributes.is_empty() else {
        @failure.reject(
          "unsupported-layout", "Ink geometry guides require support",
        )
      }
    } else if node.name == "rect" {
      self.shape_children(child, [])
      guard node.attributes.length() == 4 &&
        node.attributes.all(attribute => {
          attribute.uri.is_empty() &&
          ["l", "t", "r", "b"].contains(attribute.name) &&
          attribute.name == attribute.value
        }) else {
        @failure.reject(
          "unsupported-layout", "Ink text rectangle requires support",
        )
      }
    }
  }
  guard self.drawing_child(geometry, "pathLst") is Some(list) &&
    self.nodes[list].attributes.is_empty() &&
    self.nodes[list].text.trim().is_empty() &&
    self.children[list] is [path] &&
    self.nodes[path].uri == picture_drawing_uri &&
    self.nodes[path].name == "path" else {
    @failure.reject("unsupported-layout", "Ink requires one native path")
  }
  let node = self.nodes[path]
  let width = drawing_number(node, "w")
  let height = drawing_number(node, "h")
  guard width > 0 &&
    height > 0 &&
    node.attribute("fill") == Some("none") &&
    node.text.trim().is_empty() &&
    node.attributes.all(attribute => {
      attribute.uri.is_empty() && ["w", "h", "fill"].contains(attribute.name)
    }) &&
    self.children[path].length() >= 2 &&
    self.children[path].length() <= 4096 else {
    @failure.reject(
      "unsupported-layout", "Invalid or excessive native ink path",
    )
  }
  self.children[path].mapi((index, command) => {
    let node = self.nodes[command]
    guard node.uri == picture_drawing_uri &&
      node.name == (if index == 0 { "moveTo" } else { "lnTo" }) &&
      node.attributes.is_empty() &&
      node.text.trim().is_empty() &&
      self.children[command] is [point] else {
      @failure.reject(
        "unsupported-layout", "Ink requires move and line commands",
      )
    }
    let node = self.nodes[point]
    self.shape_children(point, [])
    let x = drawing_number(node, "x") / width
    let y = drawing_number(node, "y") / height
    guard node.uri == picture_drawing_uri &&
      node.name == "pt" &&
      node.attributes.length() == 2 &&
      node.attributes.all(attribute => {
        attribute.uri.is_empty() && ["x", "y"].contains(attribute.name)
      }) &&
      x >= 0 &&
      x <= 1 &&
      y >= 0 &&
      y <= 1 else {
      @failure.reject(
        "unsupported-layout", "Ink point lies outside its native frame",
      )
    }
    (x, y)
  })
}

///|
fn WordTree::shape_stroke_alpha(
  self : WordTree,
  line : Int32,
) -> Double raise @failure.Failure {
  let color = self
    .drawing_child(line, "solidFill")
    .bind(fill => self.drawing_child(fill, "srgbClr"))
  guard color.bind(color => self.drawing_child(color, "alpha")) is Some(alpha) else {
    return 1
  }
  let node = self.nodes[alpha]
  self.shape_children(alpha, [])
  let value = @string.parse_int(node.attribute("val").unwrap_or("")) catch {
    _ => @failure.reject("unsupported-layout", "Invalid ink stroke opacity")
  }
  guard node.attributes.length() == 1 &&
    node.attributes[0].name == "val" &&
    node.attributes[0].uri.is_empty() &&
    value >= 0 &&
    value <= 100000 else {
    @failure.reject("unsupported-layout", "Invalid ink stroke opacity")
  }
  value.to_double() / 100000
}
