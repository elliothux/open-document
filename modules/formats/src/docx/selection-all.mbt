///|
/// Selects the current body or text box story without changing document history.
pub fn Session::select_all(
  self : Session,
  revision : Int,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let tree = WordTree::new(self.document())
  let drawing = self.selection.bind(selection => {
    tree.text_box_drawing(selection.focus.paragraph)
  })
  let root = if drawing is Some(_) && self.selection is Some(selection) {
    tree.nodes[selection.focus.paragraph].parent
  } else {
    tree.child(0, "body").unwrap()
  }
  let paragraphs = tree
    .descendants(root)
    .filter(id => {
      let node = tree.nodes[id]
      node.uri == word_uri &&
      node.name == "p" &&
      tree.text_box_drawing(id) == drawing
    })
  guard paragraphs.get(0) is Some(first) && paragraphs.last() is Some(last) else {
    @failure.reject("protected-content", "Story has no selectable paragraphs")
  }
  let mut length = 0
  for text in docx_texts(tree) {
    if text.paragraph == last {
      length += inline_text(tree.nodes[text.id]).length()
    }
  }
  let anchor : Position = {
    paragraph: first,
    offset: 0,
    affinity: "after",
    bidiLevel: None,
    frameStart: None,
  }
  self.select(revision, {
    anchor,
    focus: { ..anchor, paragraph: last, offset: length, affinity: "before", },
  })
}
