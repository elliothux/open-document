///|
fn Session::prepare_plain_range(
  self : Session,
  selection : Selection,
  text : String,
  input_group~ : Int32? = None,
  check_graphemes~ : Bool = true,
  notes~ : Bool = false,
) -> PreparedEdit? raise @failure.Failure {
  guard text.length() <= command_limit else {
    @failure.reject("limit-exceeded", "Command input exceeds UTF-16 budget")
  }
  guard valid_inline_input(text) else {
    @failure.reject(
      "invalid-operation", "Invalid paragraph text or inline control",
    )
  }
  let anchor = selection.anchor
  let focus = selection.focus
  if text.iter().any(ch => ['\u2028', '\u000b', '\u000c'].contains(ch)) {
    self.check_display_math_input(selection)
  }
  if has_region_break(text) {
    let tree = WordTree::new(self.document())
    tree.check_region_break_input(anchor.paragraph, text)
    tree.check_region_break_input(focus.paragraph, text)
  }
  if input_group is Some(group) {
    guard group > 0 &&
      !text.is_empty() &&
      !text.contains("\n") &&
      !text.contains("\u2028") &&
      !has_region_break(text) &&
      !text.contains("\t") else {
      @failure.reject(
        "invalid-operation", "Input group requires a positive id and ordinary input without LF",
      )
    }
  }
  if anchor.paragraph != focus.paragraph || text.contains("\n") {
    if anchor.paragraph != focus.paragraph {
      let tree = WordTree::new(self.document())
      if self.table_cell_range(
          tree,
          selection,
          pictures=true,
          fields=true,
          math=true,
          notes~,
        )
        is Some(cells) {
        return Some(
          self.prepare_table_contents(
            tree,
            cells,
            text,
            check_graphemes~,
            notes~,
          ),
        )
      }
    }
    return Some(
      self.prepare_structural_range(selection, text, check_graphemes~, notes~),
    )
  }
  let tree = WordTree::new(self.document())
  let nodes = tree.nodes
  let texts = self.editable_texts(anchor.paragraph, notes~)
  if notes && texts.any(item => note_reference(nodes[item.id])) {
    ignore(
      self.paragraph_range(
        tree,
        selection,
        structural=false,
        fields=true,
        math=true,
        notes=true,
      ),
    )
  }
  let content = texts.map(node => inline_text(nodes[node.id])).join("")
  let boundaries = editing_boundaries(content, check_graphemes)
  validate_position(anchor, boundaries)
  validate_position(focus, boundaries)
  let start = anchor.offset.min(focus.offset)
  let end = anchor.offset.max(focus.offset)
  if content[start:end] == text &&
    !tree.has_drawing_range(texts, start, end, fields=true) {
    return None
  }
  if texts.is_empty() {
    return Some(self.prepare_empty(anchor.paragraph, text))
  }
  let affinity = if anchor.offset <= focus.offset {
    anchor.affinity
  } else {
    focus.affinity
  }
  let continuing = start == end &&
    self.selection == Some(selection) &&
    !text.is_empty()
  let insertion = for node in texts; offset = 0 {
    let length = inline_text(nodes[node.id]).length()
    if continuing &&
      self.typing_text == Some(node.id) &&
      start >= offset &&
      start <= offset + length {
      break node.id
    }
    if start < offset + length ||
      (start == offset + length && affinity == "before") {
      break node.id
    }
    continue offset + length
  } nobreak {
    texts.last().unwrap().id
  }
  let changes : Map[Int32, String] = Map([])
  let object_offsets : Map[Int32, Int32] = Map([])
  let mut offset = 0
  for node in texts {
    let before = inline_text(nodes[node.id])
    let length = before.length()
    let left = (start - offset).clamp(min=0, max=length)
    let right = (end - offset).clamp(min=0, max=length)
    let after = before[:left].to_owned() +
      (if node.id == insertion { text } else { "" }) +
      before[right:].to_owned()
    let picture = note_reference(nodes[node.id]) ||
      ["drawing", "fldSimple", "oMath", "oMathPara"].contains(
        nodes[node.id].name,
      )
    if picture && left == right {
      object_offsets[node.id] = if left == 0 && node.id == insertion {
        text.length()
      } else {
        0
      }
    }
    if before != after || (picture && left != right) {
      changes[node.id] = after
    }
    offset += length
  }
  let updated = content[:start].to_owned() + text + content[end:].to_owned()
  let caret = @layout.grapheme_boundaries(updated)
    .iter()
    .filter(offset => offset >= start + text.length())
    .next()
    .unwrap()
  let position = {
    ..anchor,
    offset: caret,
    affinity: "after",
    bidiLevel: None,
    frameStart: None,
  }
  let after : Selection = { anchor: position, focus: position, }
  let prepared = self.prepare_text(
    changes,
    Some(after),
    anchor.paragraph,
    source=tree.index_range_changes({ ..anchor, offset: start, }, {
      ..focus,
      offset: end,
    }),
    object_offsets~,
    notes~,
  )
  Some({
    ..prepared,
    typing_text: if text.is_empty() {
      None
    } else {
      Some(insertion)
    },
    join_group: continuing,
  })
}
