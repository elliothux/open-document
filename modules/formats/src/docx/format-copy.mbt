///|
fn Selection::without_visual_hints(self : Selection) -> Selection {
  {
    anchor: { ..self.anchor, bidiLevel: None, frameStart: None, },
    focus: { ..self.focus, bidiLevel: None, frameStart: None, },
  }
}

///|
/// Captures uniform effective properties; mixed properties are omitted.
pub fn Session::capture_format(
  self : Session,
  revision : Int,
  selection : Selection,
) -> Json raise @failure.Failure {
  let result = self.query_formatting(revision, selection)
  guard result
    is {
      "reason": String(reason),
      "character": Object(character),
      "paragraph": Object(paragraph),
      ..
    } else {
    abort("Invalid internal formatting result")
  }
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let groups : Map[String, Json] = Map([])
  for (name, fields) in [("character", character), ("paragraph", paragraph)] {
    let values : Map[String, Json] = Map([])
    for key, field in fields {
      if key != "style" &&
        field is { "kind": String("value"), "value": value, .. } {
        values[key] = value
      }
    }
    groups[name] = Json(values)
  }
  Json(groups)
}

///|
/// Applies both property groups atomically as one history entry.
pub fn Session::apply_format(
  self : Session,
  revision : Int,
  selection : Selection,
  character : CharacterFormat,
  paragraph : ParagraphFormat,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  character.validate()
  if character.style is Set(key) {
    self.styles([]).validate_style(key, "character")
  }
  ignore(paragraph.properties())
  let document = self.document()
  let range = self.formatting_range(
    document,
    selection,
    whole_cells=true,
    fields=true,
    notes=true,
  )
  let collapsed = range.start.paragraph == range.end.paragraph &&
    range.start.offset == range.end.offset
  let pending = if self.selection == Some(selection) {
    self.typing_format
  } else {
    None
  }
  let mut candidate = document
  let edits : Array[@xml.Edit] = []
  if !collapsed &&
    self.format_character_document(candidate, selection, character, fields=true)
    is Some((updated, edit)) {
    candidate = updated
    edits.push(edit)
  }
  if self.format_paragraph_document(
      candidate,
      selection,
      paragraph,
      fields=true,
    )
    is Some((updated, edit)) {
    candidate = updated
    edits.push(edit)
  }
  let mut bytes = 0
  for edit in edits {
    let count = edit_bytes(edit)
    guard count <= history_byte_limit - bytes else {
      @failure.reject("limit-exceeded", "Copied format history budget exceeded")
    }
    bytes += count
  }
  let selection = if edits.is_empty() {
    selection
  } else {
    selection.without_visual_hints()
  }
  if !edits.is_empty() {
    self.commit_edit(
      {
        xml: edits,
        parts: Map([]),
        created: Map([]),
        created_media: Map([]),
        before: self.selection,
        after: Some(selection),
        paragraphs: range.paragraphs,
        bytes,
      },
      candidate,
    )
  }
  if collapsed && !character.properties().is_empty() {
    self.typing_format = Some(
      pending.unwrap_or(CharacterFormat::new()).merge(character),
    )
    self.selection = Some(selection)
    self.typing_text = None
    self.input_group = None
  } else if character.properties().is_empty() {
    self.typing_format = pending
  }
  self.edit_result(range.paragraphs)
}
