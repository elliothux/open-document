///|
/// Body Tab applies list rules or inserts a tab; cell Tab changes selection.
pub fn Session::tab(
  self : Session,
  revision : Int,
  backward : Bool,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  guard self.selection is Some(selection) else {
    @failure.reject("invalid-position", "Select a document position first")
  }
  let tree = WordTree::new(self.document())
  self.check_position(selection.anchor)
  self.check_position(selection.focus)
  let p = tree.nodes[selection.focus.paragraph]
  let parent = tree.nodes[p.parent]
  if parent.name == "body" {
    if self.list_tab(revision, selection, backward) is Some(result) {
      return result
    }
    if !backward {
      return self.replace_range(revision, selection, "\t")
    }
    let paragraph = self.paragraph(tree, self.styles([]), p.id, [])
    if paragraph.first > 0 {
      return self.set_paragraph_format(
        revision,
        selection,
        ParagraphFormat::new(
          first=Set((paragraph.first - paragraph.defaultTab).max(0)),
        ),
      )
    }
    if paragraph.left > 0 {
      return self.set_paragraph_format(
        revision,
        selection,
        ParagraphFormat::new(
          left=Set((paragraph.left - paragraph.defaultTab).max(0)),
        ),
      )
    }
    return self.edit_state()
  }
  guard parent.name == "tc" else {
    @failure.reject("protected-content", "Tab is inside a protected container")
  }
  let table = tree.nodes[tree.nodes[parent.parent].parent]
  let cells : Array[Int] = []
  for row in tree.children[table.id] {
    if tree.nodes[row].uri == word_uri && tree.nodes[row].name == "tr" {
      for cell in tree.children[row] {
        if tree.nodes[cell].uri == word_uri && tree.nodes[cell].name == "tc" {
          cells.push(cell)
        }
      }
    }
  }
  let current = cells.search(parent.id).unwrap()
  let next = current + (if backward { -1 } else { 1 })
  guard cells.get(next) is Some(cell) else {
    return if backward {
      self.edit_state()
    } else {
      self.edit_table(revision, selection, RowAfter)
    }
  }
  guard tree.child(cell, "p") is Some(paragraph) else {
    @failure.reject(
      "protected-content", "Target cell has no editable paragraph",
    )
  }
  let position : Position = {
    paragraph,
    offset: 0,
    affinity: "after",
    frameStart: None,
    bidiLevel: None,
  }
  self.select(revision, { anchor: position, focus: position, })
}
