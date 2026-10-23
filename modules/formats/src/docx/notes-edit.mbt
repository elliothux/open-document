///|
fn check_note_text(text : String) -> Unit raise @failure.Failure {
  guard text.length() <= 32767 &&
    @xml.valid_text(text) &&
    text
    .iter()
    .all(c => {
      (c == '\n' || c.to_int() >= 32) &&
      c != '\u007f' &&
      c != '\u2028' &&
      c != '\u2029'
    }) else {
    @failure.reject(
      "invalid-operation", "Note text requires valid paragraphs of at most32767 units",
    )
  }
}

///|
/// Updates a plain note body while retaining its marker, run properties and body references.
pub fn Session::edit_note(
  self : Session,
  revision : Int,
  kind : String,
  key : String,
  text : String,
  probe~ : @layout.TextProbe,
  profile~ : Map[String, String],
  images~ : @layout.Images,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  check_note_text(text)
  let key = note_key(key)
  guard self.note_source(kind) is Some(source) &&
    source.entries.iter().find_first(entry => entry.key == key) is Some(note) else {
    @failure.reject("invalid-operation", "Unknown note identity")
  }
  guard note.reason.is_empty() else {
    @failure.reject(
      "protected-content", "Structured or opaque note content is protected",
    )
  }
  guard source.entries
    .iter()
    .fold(init=text.length(), (sum, entry) => {
      sum + (if entry.key == key { 0 } else { entry.text.length() })
    }) <=
    1048576 else {
    @failure.reject("limit-exceeded", "Note catalog text exceeds limits")
  }
  if note.text == text {
    return self.edit_state()
  }
  let (candidate, steps) = source.edit_text(note, text)
  let parts = self.parts.copy()
  parts[source.part] = candidate
  let flow = { ..self, parts, }.flow()
  if !flow.notes.is_empty() {
    ignore(@layout.paginate(probe, flow, profile, images))
  }
  let edits = Map([(source.part, steps)])
  let bytes = xml_part_edit_bytes(edits, Map([]))
  self.commit_edit(
    {
      xml: [],
      parts: edits,
      created: Map([]),
      created_media: Map([]),
      before: self.selection,
      after: self.selection,
      paragraphs: [],
      bytes,
    },
    self.document(),
    parts~,
  )
  self.edit_result([])
}
