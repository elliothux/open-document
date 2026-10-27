///|
fn is_docx_note_operation(operation : String) -> Bool {
  [
    "docxNotes", "editDocxNote", "insertDocxNote", "removeDocxNote", "setEndnotePosition",
    "noteNumbering", "setNoteNumbering",
  ].contains(operation)
}

///|
fn Foundation::docx_note_operation(
  self : Foundation,
  operation : String,
  request : Json,
) -> Json raise @failure.Failure {
  guard self.docx is Some(session) else {
    @failure.reject("invalid-operation", "Open a DOCX session first")
  }
  let revision = field_int(request, "revision")
  if operation == "docxNotes" {
    return session.notes(revision)
  }
  if operation == "noteNumbering" {
    return session.note_numbering(
      revision,
      field_string(request, "kind"),
      field_int(request, "section"),
    )
  }
  if operation == "setNoteNumbering" {
    guard request is { "numbering": Object(fields) as value, .. } &&
      fields.length() == 3 &&
      fields.keys().all(key => ["format", "start", "restart"].contains(key)) else {
      @failure.reject("invalid-operation", "Invalid note numbering fields")
    }
    let start = xlsx_number(value, "start")
    guard start >= 0 && start <= 4294967295 && start.floor() == start else {
      @failure.reject("invalid-operation", "Invalid note numbering start")
    }
    let result = session.set_note_numbering(
      revision,
      field_string(request, "kind"),
      field_int(request, "section"),
      @layout.PageNumbering::new(
        start=start.to_int64(),
        format=field_string(value, "format"),
      ),
      field_string(value, "restart"),
      probe=self.probe,
      profile=xlsx_profile(request),
      images=self.images,
    )
    if result is { "revision": Number(current, ..), .. } &&
      current != revision.to_double() {
      self.layout = None
    }
    return result
  }
  if operation == "setEndnotePosition" {
    let result = session.set_endnote_position(
      revision,
      field_string(request, "position"),
      probe=self.probe,
      profile=xlsx_profile(request),
      images=self.images,
    )
    if result is { "revision": Number(current, ..), .. } &&
      current != revision.to_double() {
      self.layout = None
    }
    return result
  }
  let keys = if operation == "insertDocxNote" {
    ["kind", "text"]
  } else if operation == "removeDocxNote" {
    ["kind", "id"]
  } else {
    ["kind", "id", "text"]
  }
  guard request is { "note": Object(fields) as note, .. } &&
    fields.length() == keys.length() &&
    fields.keys().all(key => keys.contains(key)) else {
    @failure.reject("invalid-operation", "Invalid native note fields")
  }
  let kind = field_string(note, "kind")
  let profile = xlsx_profile(request)
  let result = match operation {
    "insertDocxNote" =>
      session.insert_note(
        revision,
        kind,
        field_string(note, "text"),
        probe=self.probe,
        profile~,
        images=self.images,
      )
    "removeDocxNote" =>
      session.remove_note(
        revision,
        kind,
        field_string(note, "id"),
        probe=self.probe,
        profile~,
        images=self.images,
      )
    "editDocxNote" =>
      session.edit_note(
        revision,
        kind,
        field_string(note, "id"),
        field_string(note, "text"),
        probe=self.probe,
        profile~,
        images=self.images,
      )
    _ => @failure.reject("invalid-operation", "Unknown native note operation")
  }
  if result is { "revision": Number(current, ..), .. } &&
    current != revision.to_double() {
    self.layout = None
  }
  result
}
