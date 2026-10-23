///|
/// Updates a plain note body while retaining its marker, run properties and body references.
pub fn Session::edit_note(
  self : Session,
  revision : Int,
  kind : String,
  key : String,
  text : String,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  guard text.length() <= 32767 &&
    @xml.valid_text(text) &&
    text
    .iter()
    .all(c => {
      c.to_int() >= 32 && c != '\u007f' && c != '\u2028' && c != '\u2029'
    }) else {
    @failure.reject(
      "invalid-operation", "Note text must be a valid single line of at most32767 units",
    )
  }
  let key = note_key(key)
  guard self.note_source(kind) is Some(source) &&
    source.entries.iter().find_first(entry => entry.key == key) is Some(note) else {
    @failure.reject("invalid-operation", "Unknown note identity")
  }
  guard note.reason.is_empty() && note.paragraph is Some(paragraph) else {
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
  let (edited, edit) = if note.texts.get(0) is Some(first) {
    let changes : Map[Int, String] = Map([])
    for id in note.texts {
      changes[id] = if id == first { text } else { "" }
    }
    source.document.edit_text(changes)
  } else {
    let node = source.tree.nodes[paragraph]
    source.document.edit_source([
      {
        node: paragraph,
        offset: node.closing_start - node.start,
        length: 0,
        xml: "<od:r xmlns:od=\"\{word_uri}\"><od:t xml:space=\"preserve\">\{@xml.escape_text(text)}</od:t></od:r>",
      },
    ])
  }
  let steps = [edit]
  let mut candidate = edited
  if note.texts.get(0) is Some(first) && text.trim().to_owned() != text {
    let node = WordTree::new(candidate).nodes[first]
    let attribute = node.attributes
      .iter()
      .find_first(a => {
        a.uri == "http://www.w3.org/XML/1998/namespace" && a.name == "space"
      })
    if attribute.map(a => a.value) != Some("preserve") {
      let change : @xml.SourceChange = match attribute {
        Some(attribute) =>
          {
            node: first,
            offset: attribute.start - node.start,
            length: attribute.end - attribute.start,
            xml: "preserve",
          }
        None =>
          {
            node: first,
            offset: node.opening_end - node.start - 1,
            length: 0,
            xml: " xml:space=\"preserve\"",
          }
      }
      let (updated, edit) = candidate.edit_source([change])
      candidate = updated
      steps.push(edit)
    }
  }
  let parts = self.parts.copy()
  parts[source.part] = candidate
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
