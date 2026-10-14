///|
priv struct ParagraphRange {
  start : Position
  end : Position
  paragraphs : Array[Int]
}

///|
fn Session::paragraph_range(
  self : Session,
  tree : WordTree,
  selection : Selection,
  structural~ : Bool,
) -> ParagraphRange raise @failure.Failure {
  self.check_position_in(self.document(), selection.anchor)
  self.check_position_in(self.document(), selection.focus)
  let (start, end) = if tree.nodes[selection.anchor.paragraph].start <
    tree.nodes[selection.focus.paragraph].start ||
    (
      selection.anchor.paragraph == selection.focus.paragraph &&
      selection.anchor.offset <= selection.focus.offset
    ) {
    (selection.anchor, selection.focus)
  } else {
    (selection.focus, selection.anchor)
  }
  let first = tree.nodes[start.paragraph]
  let last = tree.nodes[end.paragraph]
  guard first.parent == last.parent else {
    @failure.reject("protected-content", "Range crosses paragraph containers")
  }
  let siblings = tree.children[first.parent]
  let paragraphs = siblings[siblings.search(first.id).unwrap():siblings
  .search(last.id)
  .unwrap() +
  1].to_owned()
  for id in paragraphs {
    guard tree.nodes[id].uri == word_uri && tree.nodes[id].name == "p" else {
      @failure.reject("protected-content", "Range crosses protected content")
    }
    tree.check_editable_paragraph(id, part=self.main)
    if structural {
      tree.check_structure_paragraph(id)
    }
  }
  let flow = self.flow_from(self.document())
  let all = flow.paragraphs.copy()
  for table in flow.tables {
    for row in table.rows {
      for cell in row {
        all.append(cell)
      }
    }
  }
  let reasons = Map::from_array(all.map(p => (p.id, p.readOnlyReason)))
  for id in paragraphs {
    guard reasons.get(id) == Some("") else {
      @failure.reject("protected-content", "Range crosses protected content")
    }
  }
  { start, end, paragraphs, }
}

///|
/// Reads a supported plain-text range in document order, with LF paragraph separators.
/// This query preserves selection, revision, history and layout; oversized output fails.
pub fn Session::selected_text(
  self : Session,
  revision : Int,
  selection : Selection,
) -> String raise @failure.Failure {
  self.check_revision(revision)
  let tree = WordTree::new(self.document())
  let range = self.paragraph_range(tree, selection, structural=false)
  let output = StringBuilder()
  let mut units = 0
  for index, paragraph in range.paragraphs {
    let text = self
      .editable_texts(paragraph)
      .map(node => tree.nodes[node.id].text)
      .join("")
    let start = if paragraph == range.start.paragraph {
      range.start.offset
    } else {
      0
    }
    let end = if paragraph == range.end.paragraph {
      range.end.offset
    } else {
      text.length()
    }
    units += end - start + (if index > 0 { 1 } else { 0 })
    guard units <= command_limit else {
      @failure.reject("limit-exceeded", "Selection text exceeds UTF-16 budget")
    }
    if index > 0 {
      output.write_string("\n")
    }
    output.write_string(text[start:end].to_owned())
  }
  output.to_string()
}
