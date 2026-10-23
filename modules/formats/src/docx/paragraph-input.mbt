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
  let tree = WordTree::new(self.document())
  let input_selection = match
    self.table_cell_range(
      tree,
      selection,
      pictures=true,
      fields=true,
      math=true,
      notes=true,
    ) {
    Some(cells) =>
      tree.cell_contents_selection(cells.owners[0], docx_texts(tree))
    None => selection
  }
  let prepared = if selection.anchor.paragraph != selection.focus.paragraph ||
    selection.anchor.offset != selection.focus.offset {
    self.prepare_range(input_selection, "")
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
  let length = docx_texts(tree)
    .filter(node => node.paragraph == caret.focus.paragraph)
    .fold(init=0, (sum, node) => sum + inline_text(tree.nodes[node.id]).length())
  let styles = self.styles([])
  if caret.focus.offset == length &&
    styles.next_paragraph_style(tree, caret.focus.paragraph) is Some(next) {
    let prepared = self.prepare_range(selection, "\n").unwrap()
    let after = prepared.edit.after.unwrap()
    let bidi = tree
      .child(caret.focus.paragraph, "pPr")
      .bind(id => tree.child(id, "bidi"))
      .map(id => {
        !["0", "false", "off"].contains(
          tree.nodes[id].attribute("val", uri=word_uri).unwrap_or("1"),
        )
      })
    let (document, xml) = self
      .format_paragraph_document(
        prepared.document,
        after,
        ParagraphFormat::new(
          style=Set(next),
          rtl=bidi.map(value => Set(value)).unwrap_or(Keep),
        ),
      )
      .unwrap()
    let bytes = edit_bytes(xml)
    guard bytes <= history_byte_limit - prepared.edit.bytes else {
      @failure.reject(
        "limit-exceeded", "Paragraph input history budget exceeded",
      )
    }
    let edits = prepared.edit.xml.copy()
    edits.push(xml)
    self.commit_edit(
      { ..prepared.edit, xml: edits, bytes: prepared.edit.bytes + bytes, },
      document,
    )
    self.typing_text = prepared.typing_text
    return self.edit_result(prepared.edit.paragraphs)
  }
  self.replace_range(revision, selection, "\n")
}

///|
fn Styles::next_paragraph_style(
  self : Styles,
  tree : WordTree,
  paragraph : Int,
) -> String? {
  let current = match
    tree.child(paragraph, "pPr").bind(id => tree.value(id, "pStyle")) {
    Some(key) => Some(key)
    None => self.default_paragraph
  }
  guard current is Some(current) &&
    self.tree is Some(source) &&
    self.ids.get(current) is Some(id) &&
    source.value(id, "next") is Some(next) &&
    next != current &&
    self.ids.get(next) is Some(target) &&
    source.nodes[target].attribute("type", uri=word_uri).unwrap_or("paragraph") ==
    "paragraph" else {
    return None
  }
  Some(next)
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
