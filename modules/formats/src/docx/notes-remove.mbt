///|
/// Removes one ordinary note and its uniquely owned body reference in one transaction.
pub fn Session::remove_note(
  self : Session,
  revision : Int,
  kind : String,
  key : String,
  probe~ : @layout.TextProbe,
  profile~ : Map[String, String],
  images~ : @layout.Images,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
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
  let document = self.document()
  let tree = WordTree::new(document)
  let references : Array[Int] = []
  for part in self.style_part_names() {
    let current = self.part_xml(part)
    for node in current.nodes() {
      if node.uri == word_uri &&
        node.name == kind + "Reference" &&
        note_key(node.attribute("id", uri=word_uri).unwrap_or("")) == key {
        guard part == self.main else {
          @failure.reject(
            "protected-content", "Note reference belongs to another content story",
          )
        }
        references.push(node.id)
      }
    }
  }
  guard references.length() <= 1 else {
    @failure.reject(
      "protected-content", "Repeated note references require reference-specific deletion",
    )
  }
  let mut candidate = document
  let xml : Array[@xml.Edit] = []
  let paragraphs : Array[Int] = []
  let mut after = self.selection
  if references.get(0) is Some(id) {
    let node = tree.nodes[id]
    let paragraph = tree.run_paragraph(node.parent)
    self.check_note_paragraph(document, paragraph)
    let offset = self.texts
      .filter(item => {
        item.paragraph == paragraph && tree.nodes[item.id].start < node.start
      })
      .fold(init=0, (value, item) => {
        value + inline_text(tree.nodes[item.id]).length()
      })
    let run = tree.nodes[node.parent]
    let whole_run = tree.children[run.id].all(child => {
        child == id || tree.nodes[child].name == "rPr"
      }) &&
      !document.source()[run.start:run.end].contains("<!--") &&
      !document.source()[run.start:run.end].contains("<?")
    let removed = if whole_run { run } else { node }
    let parent = tree.nodes[removed.parent]
    let (updated, step) = document.edit_source([
      {
        node: parent.id,
        offset: removed.start - parent.start,
        length: removed.end - removed.start,
        xml: "",
      },
    ])
    candidate = updated
    xml.push(step)
    paragraphs.push(paragraph)
    let text = docx_texts(WordTree::new(candidate))
      .filter(item => item.paragraph == paragraph)
      .map(item => inline_text(candidate.node(item.id)))
      .join("")
    let offset = editing_boundaries(text, true)
      .iter()
      .find_first(value => value >= offset)
      .unwrap_or(text.length())
    let caret : Position = {
      paragraph,
      offset,
      affinity: "after",
      bidiLevel: None,
      frameStart: None,
    }
    self.check_position_in(candidate, caret)
    after = Some({ anchor: caret, focus: caret, })
  }
  let node = source.tree.nodes[note.node]
  let (story, step) = source.document.edit_source([
    {
      node: 0,
      offset: node.start - source.tree.nodes[0].start,
      length: node.end - node.start,
      xml: "",
    },
  ])
  let parts = self.parts.copy()
  parts[source.part] = story
  self.commit_note_command(
    candidate,
    xml,
    parts,
    Map([(source.part, [step])]),
    Map([]),
    after,
    paragraphs,
    probe~,
    profile~,
    images~,
  )
}
