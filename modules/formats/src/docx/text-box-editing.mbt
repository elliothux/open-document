///|
fn WordTree::text_box_drawing(self : WordTree, paragraph : Int32) -> Int32? {
  guard self.nodes.get(paragraph) is Some(node) &&
    self.nodes.get(node.parent) is Some(parent) &&
    parent.uri == word_uri &&
    parent.name == "txbxContent" else {
    return None
  }
  for ancestor = parent.parent
      ancestor >= 0
      ancestor = self.nodes[ancestor].parent {
    let node = self.nodes[ancestor]
    if node.uri == word_uri && node.name == "drawing" {
      return Some(ancestor)
    }
    if node.uri == word_uri && ["body", "tc", "p"].contains(node.name) {
      break
    }
  }
  None
}

///|
fn Session::check_text_box_paragraph(
  self : Session,
  tree : WordTree,
  paragraph : Int32,
) -> Unit raise @failure.Failure {
  if tree.text_box_drawing(paragraph) is Some(drawing) {
    ignore(self.editable_shape(tree, drawing))
    guard !tree.shape_locked(drawing, "noTextEdit") &&
      !tree.shape_locked(drawing, "noSelect") else {
      @failure.reject("protected-content", "Text box text editing is locked")
    }
  }
}
