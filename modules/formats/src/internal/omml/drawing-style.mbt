///|
fn Tree::drawing_style(
  self : Tree,
  id : Int,
  base : @layout.TextStyle,
) -> @layout.TextStyle raise @failure.Failure {
  let node = self.nodes[id]
  guard node.name == "rPr" &&
    node.text.trim().is_empty() &&
    node.attributes.all(attribute => {
      attribute.uri.is_empty() &&
      ["sz", "lang", "altLang", "dirty", "smtClean", "b", "i"].contains(
        attribute.name,
      ) &&
      (
        !["b", "i"].contains(attribute.name) ||
        ["0", "false"].contains(attribute.value)
      )
    }) else {
    @failure.reject(
      "unsupported-math", "Extended DrawingML math font properties",
    )
  }
  let size = match node.attribute("sz") {
    None => base.size
    Some(value) => {
      let size = @string.parse_int(value[:]) catch {
        _ =>
          @failure.reject(
            "unsupported-math", "Invalid DrawingML math font size",
          )
      }
      size.to_double() / 100
    }
  }
  guard size >= 0.5 && size <= 409 else {
    @failure.reject(
      "unsupported-math", "DrawingML math font size exceeds limits",
    )
  }
  let mut family = base.font
  let mut color = base.color
  let seen : Set[String] = Set([])
  let fonts : Array[String] = []
  for child in self.children[id] {
    let node = self.nodes[child]
    guard node.uri == drawing_uri &&
      ["latin", "ea", "cs", "solidFill"].contains(node.name) &&
      !seen.contains(node.name) &&
      node.text.trim().is_empty() else {
      @failure.reject("unsupported-math", "Extended DrawingML math appearance")
    }
    seen.add(node.name)
    if node.name == "solidFill" {
      guard node.attributes.is_empty() && self.children[child] is [value] else {
        @failure.reject("unsupported-math", "Math requires a single RGB fill")
      }
      let rgb = self.nodes[value]
      guard rgb.uri == drawing_uri &&
        rgb.name == "srgbClr" &&
        rgb.attributes.length() == 1 &&
        rgb.attribute("val") is Some(value) &&
        value.length() == 6 &&
        value.iter().all(c => c.is_ascii_hexdigit()) &&
        rgb.text.is_empty() &&
        self.children[rgb.id].is_empty() else {
        @failure.reject("unsupported-math", "Math requires a plain RGB fill")
      }
      color = value.to_lower()
    } else {
      guard node.attributes.length() == 1 &&
        node.attribute("typeface") is Some(value) &&
        self.children[child].is_empty() &&
        value.length() <= 255 &&
        !value.has_prefix("+") else {
        @failure.reject(
          "unsupported-math", "Math requires literal uniform font families",
        )
      }
      if !value.is_empty() {
        fonts.push(value)
        if node.name == "latin" {
          family = value
        }
      }
    }
  }
  guard fonts.all(value => value == family) else {
    @failure.reject("unsupported-math", "Math requires one font family")
  }
  { ..base, font: family, size, color, }
}
