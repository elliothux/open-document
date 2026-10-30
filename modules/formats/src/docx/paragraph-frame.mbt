///|
fn WordTree::paragraph_frame(
  self : WordTree,
  paragraph : Int32,
) -> @layout.ParagraphFrame? raise @failure.Failure {
  guard self.child(paragraph, "pPr").bind(p => self.child(p, "framePr"))
    is Some(id) else {
    return None
  }
  let node = self.nodes[id]
  guard self.children[id].is_empty() &&
    node.text.trim().is_empty() &&
    node.attributes.all(a => {
      a.uri == word_uri &&
      [
        "w", "h", "hRule", "hSpace", "vSpace", "wrap", "hAnchor", "vAnchor", "x",
        "y", "xAlign", "yAlign",
      ].contains(a.name)
    }) &&
    node.attribute("wrap", uri=word_uri) == Some("notBeside") else {
    @failure.reject("unsupported-layout", "Unsupported native paragraph frame")
  }
  let props = self.nodes[id].parent
  fn number(name : String) -> Double? raise @failure.Failure {
    self.number(props, "framePr", name).map(value => value / 20)
  }
  let width = number("w").unwrap_or(0)
  let height = number("h").unwrap_or(0)
  let horizontal_space = number("hSpace").unwrap_or(0)
  let vertical_space = number("vSpace").unwrap_or(0)
  let x = number("x")
  let y = number("y")
  let horizontal_anchor = node
    .attribute("hAnchor", uri=word_uri)
    .unwrap_or("margin")
  let vertical_anchor = node
    .attribute("vAnchor", uri=word_uri)
    .unwrap_or("text")
  let horizontal_align = node.attribute("xAlign", uri=word_uri).unwrap_or("")
  let vertical_align = node.attribute("yAlign", uri=word_uri).unwrap_or("")
  let rule = node
    .attribute("hRule", uri=word_uri)
    .unwrap_or(if height > 0 { "atLeast" } else { "auto" })
  guard [width, height, horizontal_space, vertical_space].all(v => {
      v >= 0 && v <= 14400
    }) &&
    [x, y].all(v => v.map(v => v.abs() <= 14400).unwrap_or(true)) &&
    ["page", "margin", "text"].contains(horizontal_anchor) &&
    ["page", "margin", "text"].contains(vertical_anchor) &&
    ["", "left", "right", "center", "inside", "outside"].contains(
      horizontal_align,
    ) &&
    ["", "top", "bottom", "center", "inside", "outside"].contains(
      vertical_align,
    ) &&
    ["auto", "atLeast", "exact"].contains(rule) else {
    @failure.reject(
      "unsupported-layout", "Invalid native paragraph frame geometry",
    )
  }
  let borders : Map[String, (Double, @layout.BorderStyle)] = Map([])
  if self.child(props, "pBdr") is Some(edges) {
    guard self.nodes[edges].attributes.is_empty() &&
      self.nodes[edges].text.trim().is_empty() else {
      @failure.reject(
        "unsupported-layout", "Unknown paragraph frame border properties",
      )
    }
    for edge in self.children[edges] {
      let border = self.nodes[edge]
      guard border.uri == word_uri &&
        ["top", "left", "bottom", "right"].contains(border.name) &&
        !borders.contains(border.name) &&
        self.children[edge].is_empty() &&
        border.text.trim().is_empty() &&
        border.attributes.all(a => {
          a.uri == word_uri && ["val", "sz", "space", "color"].contains(a.name)
        }) &&
        border.attribute("val", uri=word_uri) == Some("single") else {
        @failure.reject(
          "unsupported-layout", "Unsupported paragraph frame border",
        )
      }
      let width = self.number(edges, border.name, "sz").unwrap_or(8) / 8
      let space = self.number(edges, border.name, "space").unwrap_or(0)
      let color = border.attribute("color", uri=word_uri).unwrap_or("auto")
      guard width >= 0.25 &&
        width <= 12 &&
        space >= 0 &&
        space <= 31 &&
        (
          color == "auto" ||
          (color.length() == 6 && color.iter().all(c => c.is_ascii_hexdigit()))
        ) else {
        @failure.reject("unsupported-layout", "Invalid paragraph frame border")
      }
      borders[border.name] = (
        space,
        {
          style: "single",
          width,
          color: if color == "auto" {
            "000000"
          } else {
            color.to_lower()
          },
        },
      )
    }
  }
  Some({
    width,
    height,
    heightRule: rule,
    horizontalAnchor: horizontal_anchor,
    verticalAnchor: vertical_anchor,
    x,
    y,
    horizontalAlign: horizontal_align,
    verticalAlign: vertical_align,
    horizontalSpace: horizontal_space,
    verticalSpace: vertical_space,
    borders,
  })
}
