///|
/// Handles paragraph Enter independently of pasted paragraph separators.
pub fn Session::enter(
  self : Session,
  revision : Int,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  guard self.selection is Some(selection) else {
    @failure.reject("invalid-position", "Select a document position first")
  }
  self.check_position(selection.anchor)
  self.check_position(selection.focus)
  let prepared = if selection.anchor.paragraph != selection.focus.paragraph ||
    selection.anchor.offset != selection.focus.offset {
    self.prepare_range(selection, "")
  } else {
    None
  }
  let document = prepared
    .map(p => p.document)
    .unwrap_or_else(() => self.document())
  let caret = prepared.bind(p => p.edit.after).unwrap_or(selection)
  let tree = WordTree::new(document)
  if caret.focus.offset == 0 &&
    docx_texts(tree)
    .filter(node => node.paragraph == caret.focus.paragraph)
    .all(node => inline_text(tree.nodes[node.id]).is_empty()) &&
    self.list_boundary_input(revision, caret, enter=true, prepared~)
    is Some(result) {
    return result
  }
  self.replace_range(revision, selection, "\n")
}

///|
fn Session::list_boundary_input(
  self : Session,
  revision : Int,
  selection : Selection,
  enter~ : Bool,
  prepared~ : PreparedEdit? = None,
) -> Json? raise @failure.Failure {
  let document = prepared
    .map(p => p.document)
    .unwrap_or_else(() => self.document())
  let tree = WordTree::new(document)
  guard self.styles([]).numbering_reference(tree, selection.focus.paragraph)
    is Some((instance, level)) else {
    return None
  }
  let clear = ParagraphFormat::new(left=Clear, first=Clear)
  if level > 0 {
    return Some(
      self.edit_list_with_indent(
        revision,
        selection,
        Apply(instance, level - 1),
        if enter {
          ParagraphFormat::new()
        } else {
          clear
        },
        prepared~,
      ),
    )
  }
  let paragraph = self.formatting_paragraphs(document, [
      selection.focus.paragraph,
    ])[0]
  Some(
    self.edit_list_with_indent(
      revision,
      selection,
      Remove,
      if enter {
        clear
      } else {
        ParagraphFormat::new(
          left=Set(paragraph.left.max(paragraph.left + paragraph.first)),
          first=Set(0),
        )
      },
      prepared~,
    ),
  )
}
