///|
fn Session::selected_drawing(self : Session, tree : WordTree) -> Int32? {
  guard self.selection is Some(selection) &&
    selection.anchor.paragraph == selection.focus.paragraph &&
    (selection.anchor.offset - selection.focus.offset).abs() == 1 else {
    return None
  }
  let start = selection.anchor.offset.min(selection.focus.offset)
  for
    item in self.texts.filter(item => {
      item.paragraph == selection.anchor.paragraph
    })
    cursor = 0 {
    if cursor == start && tree.nodes[item.id].name == "drawing" {
      return Some(item.id)
    }
    continue cursor + inline_text(tree.nodes[item.id]).length()
  }
  None
}
