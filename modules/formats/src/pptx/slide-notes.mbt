///|
fn Session::set_notes(
  self : Session,
  index : Int,
  text : String,
) -> Json raise @failure.Failure {
  guard text.length() <= 32767 && @xml.valid_text(text) else {
    @failure.reject(
      "invalid-text", "Notes require valid text within 32767 UTF-16 units",
    )
  }
  let text = text
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\r", new="\n")
  guard text.split("\n").count() <= 256 &&
    text.split("\n").all(line => line.length() <= 4096) else {
    @failure.reject("limit-exceeded", "Notes exceed paragraph budget")
  }
  let slide = self.slides[index].tree.part
  let notes = self.read_notes(slide)
  if notes.map(n => n.text).unwrap_or("") == text {
    return self.query()
  }
  let parts = self.parts.copy()
  let created : Map[String, @xml.Document] = Map([])
  let edits : Array[(String, @xml.Edit)] = []
  if notes is Some(notes) {
    let tree = notes.tree
    let changes = if notes.shape is Some(shape) {
      let body = tree.required(shape.node.id, "txBody", uri=presentation_uri)
      let markup = notes_paragraphs(notes, text)
      if notes.paragraphs.is_empty() {
        [insertion(body, markup)]
      } else {
        let first = notes.paragraphs[0]
        let last = notes.paragraphs.last().unwrap()
        [
          {
            node: body.id,
            offset: first.start - body.start,
            length: last.end - first.start,
            xml: markup,
          },
        ]
      }
    } else {
      [insertion(shape_tree(tree), self.notes_shape(Some(tree), text))]
    }
    let (document, edit) = tree.document.edit_source(changes)
    parts[tree.part] = document
    edits.push((tree.part, edit))
  } else {
    self.create_notes(slide, text, parts, created, edits)
  }
  self.commit_slides(
    self.main,
    self.slides,
    edits,
    self.selection,
    parts~,
    created_parts=created,
  )
  self.query()
}
