///|
/// Deletes the current range or one logical extended grapheme, without layout rules.
pub fn Session::delete(
  self : Session,
  revision : Int,
  direction : String,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  guard direction == "backward" || direction == "forward" else {
    @failure.reject("invalid-operation", "Unknown deletion direction")
  }
  guard self.selection is Some(selection) else {
    @failure.reject("invalid-position", "Select a document position first")
  }
  if selection.anchor.paragraph != selection.focus.paragraph ||
    selection.anchor.offset != selection.focus.offset {
    return self.replace_range(revision, selection, "")
  }
  let focus = selection.focus
  self.check_position(focus)
  let document = self.document()
  let text = self
    .editable_texts(focus.paragraph, notes=true)
    .map(node => inline_text(document.node(node.id)))
    .join("")
  if direction == "backward" &&
    focus.offset == 0 &&
    self.list_boundary_input(revision, selection, enter=false) is Some(result) {
    return result
  }
  let boundaries = @layout.grapheme_boundaries(text)
  let index = boundaries.search(focus.offset).unwrap()
  let target = if direction == "backward" { index - 1 } else { index + 1 }
  if target < 0 || target >= boundaries.length() {
    let tree = WordTree::new(document)
    let paragraph = tree.nodes[focus.paragraph]
    let siblings = tree.children[paragraph.parent]
    let index = siblings.search(paragraph.id).unwrap()
    let adjacent = if direction == "backward" { index - 1 } else { index + 1 }
    if adjacent < 0 || adjacent >= siblings.length() {
      guard tree.nodes[paragraph.parent].name == "body" else {
        @failure.reject("protected-content", "Deletion crosses a cell boundary")
      }
      self.input_group = None
      return self.edit_state()
    }
    let node = tree.nodes[siblings[adjacent]]
    if direction == "forward" &&
      node.uri == word_uri &&
      node.name == "sectPr" &&
      adjacent == siblings.length() - 1 {
      self.input_group = None
      return self.edit_state()
    }
    guard node.uri == word_uri && node.name == "p" else {
      @failure.reject(
        "protected-content", "Paragraph boundary crosses protected content",
      )
    }
    let offset = if direction == "backward" {
      self
      .editable_texts(node.id, notes=true)
      .map(node => inline_text(document.node(node.id)))
      .join("")
      .length()
    } else {
      0
    }
    return self.replace_range(
      revision,
      {
        anchor: {
          paragraph: node.id,
          offset,
          affinity: "after",
          bidiLevel: None,
          frameStart: None,
        },
        focus,
      },
      "",
    )
  }
  self.replace_range(
    revision,
    if self.tracking_context is Some(_) ||
      WordTree::new(document).has_text_revisions(focus.paragraph) {
      { anchor: focus, focus: { ..focus, offset: boundaries[target], }, }
    } else {
      { anchor: { ..focus, offset: boundaries[target], }, focus, }
    },
    "",
  )
}
