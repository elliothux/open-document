///|
fn Tree::fraction_style(
  self : Tree,
  properties : Int,
  base : @layout.TextStyle,
) -> @layout.TextStyle raise @failure.Failure {
  let node = self.nodes[properties]
  if node.uri == drawing_uri {
    return self.drawing_style(properties, base)
  }
  guard node.uri == word_uri &&
    node.name == "rPr" &&
    node.attributes.is_empty() &&
    node.text.trim().is_empty() &&
    self.children[properties].length() == 3 &&
    self.children[properties].all(id => {
      self.nodes[id].uri == word_uri &&
      ["rFonts", "sz", "color"].contains(self.nodes[id].name) &&
      self.children[id].is_empty() &&
      self.nodes[id].text.is_empty()
    }) &&
    self.child(properties, "rFonts") is Some(fonts) &&
    self.child(properties, "sz") is Some(size) &&
    self.child(properties, "color") is Some(color) else {
    @failure.reject(
      "unsupported-math", "Fraction requires complete uniform font size and color",
    )
  }
  let font = self.nodes[fonts]
  guard font.attributes.length() == 2 &&
    font.attributes.all(a => {
      a.uri == word_uri && ["ascii", "hAnsi"].contains(a.name)
    }) &&
    font.attribute("ascii", uri=word_uri) is Some(family) &&
    font.attribute("hAnsi", uri=word_uri) == Some(family) &&
    !family.is_empty() &&
    family.length() <= 255 &&
    self.nodes[size].attributes.length() == 1 &&
    self.nodes[color].attributes.length() == 1 &&
    self.value(properties, "color") is Some(color) &&
    color.length() == 6 &&
    color.iter().all(c => c.is_ascii_hexdigit()) else {
    @failure.reject(
      "unsupported-math", "Extended mathematical font properties require support",
    )
  }
  let size = self.number(properties, "sz", "val").unwrap_or(0)
  guard size >= 1 && size <= 818 else {
    @failure.reject("unsupported-math", "Mathematical font size exceeds limits")
  }
  { ..base, font: family, size: size / 2, color: color.to_lower(), }
}
