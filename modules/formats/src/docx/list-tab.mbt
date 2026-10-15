///|
fn Session::list_tab(
  self : Session,
  revision : Int,
  selection : Selection,
  backward : Bool,
) -> Json? raise @failure.Failure {
  let document = self.document()
  let tree = WordTree::new(document)
  let styles = self.styles([])
  if selection.anchor.paragraph != selection.focus.paragraph {
    let range = self.formatting_range(document, selection)
    if range.paragraphs.any(p => styles.numbering_reference(tree, p) is Some(_)) {
      return Some(self.edit_list(revision, selection, Level(!backward)))
    }
    return None
  }
  let paragraph = selection.focus.paragraph
  guard styles.numbering_reference(tree, paragraph) is Some((instance, level)) else {
    return None
  }
  if selection.anchor.offset.min(selection.focus.offset) != 0 {
    return Some(self.replace_range(revision, selection, "\t"))
  }
  let context = self.numbering_context()
  let collapsed = selection.anchor.offset == selection.focus.offset
  if collapsed &&
    level == 0 &&
    context.counter_at(tree, styles, paragraph).values[0] <= 1 {
    return Some(
      self.shift_list_indent(revision, selection, context, instance, backward~),
    )
  }
  Some(self.edit_list(revision, selection, Level(!backward)))
}

///|
fn Session::shift_list_indent(
  self : Session,
  revision : Int,
  selection : Selection,
  context : NumberingContext,
  instance : Int,
  backward~ : Bool = false,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let definition = context.definition(instance)
  let level = context.level(instance, 0)
  let number_properties = context.tree.child(level.node, "pPr")
  guard number_properties.bind(p => context.tree.number(p, "ind", "left"))
    is Some(old) else {
    self.input_group = None
    return self.edit_state()
  }
  let document = self.document()
  let tree = WordTree::new(document)
  ignore(self.formatting_range(document, selection))
  let paragraph = self.formatting_paragraphs(document, [
      selection.focus.paragraph,
    ])[0]
  let next = if backward {
    (paragraph.left - paragraph.defaultTab).max(0).max(-paragraph.first)
  } else {
    paragraph.left + paragraph.defaultTab
  }
  let delta = next - old / 20
  let changes : Array[@xml.SourceChange] = []
  for _, value in definition.levels {
    let left = context.tree
      .child(value.node, "pPr")
      .bind(p => context.tree.number(p, "ind", "left"))
      .unwrap_or(0) /
      20 +
      delta
    let patch = ParagraphFormat::new(left=Set(left)).properties()
    let markup = formatted_properties(
      context.tree,
      context.document,
      value.node,
      "pPr",
      patch,
    )
    if properties_change(
        context.tree,
        context.document,
        value.node,
        "pPr",
        markup,
      )
      is Some(change) {
      changes.push(change)
    }
  }
  let parts = self.parts.copy()
  let edits : Map[String, Array[@xml.Edit]] = Map([])
  if !changes.is_empty() {
    let (candidate, edit) = context.document.edit_source(changes)
    parts[context.part] = candidate
    edits[context.part] = [edit]
  }
  let mut candidate = document
  let steps : Array[@xml.Edit] = []
  if self.format_paragraph_document(
      document,
      selection,
      ParagraphFormat::new(left=Clear, first=Clear),
    )
    is Some((updated, edit)) {
    candidate = updated
    steps.push(edit)
  }
  if changes.is_empty() && steps.is_empty() {
    return self.edit_state()
  }
  let mut bytes = xml_part_edit_bytes(edits, Map([]))
  for edit in steps {
    bytes += edit_bytes(edit)
  }
  guard bytes <= history_byte_limit else {
    @failure.reject("limit-exceeded", "List indent exceeds history budget")
  }
  let affected = tree.order.filter(id => {
    tree.nodes[id].uri == word_uri && tree.nodes[id].name == "p"
  })
  let styles = self.styles([])
  let changed = affected.filter(id => {
    match styles.numbering_reference(tree, id) {
      None => false
      Some((id, _)) =>
        context.definition(id).abstract_id == definition.abstract_id
    }
  })
  let view = { ..self, parts, document: Some(candidate), }
  for p in view.formatting_paragraphs(candidate, changed) {
    validate_paragraph_style_values(p)
  }
  let pending = self.typing_format
  self.commit_edit(
    {
      xml: steps,
      parts: edits,
      created: Map([]),
      before: self.selection,
      after: Some(selection.without_visual_hints()),
      paragraphs: affected,
      bytes,
    },
    candidate,
    parts~,
  )
  self.typing_format = pending
  self.edit_result(affected)
}
