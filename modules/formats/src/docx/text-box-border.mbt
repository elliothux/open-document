///|
fn WordTree::text_box_bottom_border(
  self : WordTree,
  id : Int32,
) -> (Double, @layout.BorderStyle)? raise @failure.Failure {
  let mut parent = self.nodes[id].parent
  let mut text_box = false
  while parent >= 0 {
    let node = self.nodes[parent]
    if node.uri == word_uri && node.name == "txbxContent" {
      text_box = true
      break
    }
    parent = node.parent
  }
  guard text_box &&
    self.nodes[id].attributes.is_empty() &&
    self.nodes[id].text.trim().is_empty() &&
    self.children[id] is [bottom] else {
    return None
  }
  let node = self.nodes[bottom]
  guard node.uri == word_uri &&
    node.name == "bottom" &&
    self.children[bottom].is_empty() &&
    node.text.trim().is_empty() &&
    node.attributes.all(a => {
      a.uri == word_uri && ["val", "sz", "space", "color"].contains(a.name)
    }) &&
    node.attribute("val", uri=word_uri) == Some("single") else {
    return None
  }
  let width = self.number(id, "bottom", "sz").unwrap_or(8) / 8
  let space = self.number(id, "bottom", "space").unwrap_or(0)
  let color = node.attribute("color", uri=word_uri).unwrap_or("auto")
  guard width >= 0.25 &&
    width <= 12 &&
    space >= 0 &&
    space <= 31 &&
    (
      color == "auto" ||
      (color.length() == 6 && color.iter().all(c => c.is_ascii_hexdigit()))
    ) else {
    return None
  }
  Some(
    (
      space,
      {
        style: "single",
        width,
        color: if color == "auto" {
          "000000"
        } else {
          color
        },
      },
    ),
  )
}
