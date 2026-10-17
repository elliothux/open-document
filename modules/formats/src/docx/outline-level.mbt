///|
fn WordTree::outline_level(
  self : WordTree,
  properties : Int,
) -> Int? raise @failure.Failure {
  let nodes = self.children[properties].filter(id => {
    self.nodes[id].uri == word_uri && self.nodes[id].name == "outlineLvl"
  })
  guard nodes.length() <= 1 else {
    @failure.reject("invalid-style", "Duplicate outline level")
  }
  guard nodes.get(0) is Some(id) else { return None }
  let node = self.nodes[id]
  guard self.children[id].is_empty() &&
    node.text.trim().is_empty() &&
    node.attributes.all(a => a.uri == word_uri && a.name == "val") else {
    @failure.reject("invalid-style", "Unknown outline level metadata")
  }
  let value = @string.parse_int(
    node.attribute("val", uri=word_uri).unwrap_or("")[:],
  ) catch {
    _ => @failure.reject("invalid-style", "Invalid outline level")
  }
  guard value >= 0 && value <= 9 else {
    @failure.reject(
      "invalid-style", "Outline level must be between zero and nine",
    )
  }
  Some(value)
}

///|
fn Styles::outline_level(
  self : Styles,
  tree : WordTree,
  paragraph : Int,
) -> Int? raise @failure.Failure {
  let properties = tree.child(paragraph, "pPr")
  let key = match properties.bind(id => tree.value(id, "pStyle")) {
    Some(key) => Some(key)
    None => self.default_paragraph
  }
  let mut level : Int? = None
  if self.tree is Some(source) {
    if source
      .child(0, "docDefaults")
      .bind(id => source.child(id, "pPrDefault"))
      .bind(id => source.child(id, "pPr"))
      is Some(id) {
      level = source.outline_level(id)
    }
    if key is Some(key) {
      for style in self.chain(key, []) {
        if source.child(style, "pPr").bind(id => source.outline_level(id))
          is Some(value) {
          level = Some(value)
        }
      }
    }
  }
  if properties.bind(id => tree.outline_level(id)) is Some(value) {
    level = Some(value)
  }
  level.filter(value => value < 9)
}
