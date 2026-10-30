///|
fn WordTree::alternate_branch(self : WordTree, id : Int32) -> Int32? {
  let mc = "http://schemas.openxmlformats.org/markup-compatibility/2006"
  let supported = [
    word_uri, picture_drawing_uri, picture_inline_uri, word_shape_uri,
  ]
  for child in self.children[id] {
    let node = self.nodes[child]
    if node.uri != mc || node.name != "Choice" {
      continue
    }
    let bindings = self.namespace_bindings(child)
    let required = node
      .attribute("Requires")
      .unwrap_or("")
      .split(" ")
      .filter(prefix => !prefix.is_empty())
      .to_array()
    if !required.is_empty() &&
      required.all(prefix => {
        bindings
        .get(prefix.to_owned())
        .map(uri => supported.contains(uri))
        .unwrap_or(false)
      }) {
      return Some(child)
    }
  }
  self.children[id]
  .iter()
  .find_first(child => {
    let node = self.nodes[child]
    node.uri == mc && node.name == "Fallback"
  })
}

///|
fn WordTree::select_alternate_content(self : WordTree) -> Unit {
  let mc = "http://schemas.openxmlformats.org/markup-compatibility/2006"
  // Resolve the logical tree only. Every original branch stays in the XML document.
  for id in self.order.copy() {
    let parent = self.nodes[id]
    if parent.uri == mc {
      continue
    }
    let children : Array[Int32] = []
    for child in self.children[id] {
      let node = self.nodes[child]
      if node.uri == mc &&
        node.name == "AlternateContent" &&
        self.alternate_branch(child) is Some(branch) {
        for selected in self.children[branch] {
          let original = self.nodes[selected]
          let namespaces = self.namespace_bindings(selected).iter().to_array()
          self.nodes[selected] = {
            ..original,
            parent: id,
            namespaces: ReadOnlyArray::from_array(namespaces),
          }
          children.push(selected)
        }
      } else {
        children.push(child)
      }
    }
    self.children[id] = children
  }
  self.order.clear()
  self.order.append(self.descendants(0))
}
