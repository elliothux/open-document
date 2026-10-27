///|
fn Session::section_note_settings(
  self : Session,
  tree : WordTree,
  section : Int?,
  kind : String,
) -> NoteSettings raise @failure.Failure {
  let defaults = self.note_settings(kind)
  match section {
    None => defaults
    Some(id) => defaults.read(tree, id, kind, document=false)
  }
}

///|
/// Reads one section's effective footnote or endnote numbering without changing source.
pub fn Session::note_numbering(
  self : Session,
  revision : Int,
  kind : String,
  sectionIndex : Int,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  guard ["footnote", "endnote"].contains(kind) &&
    sectionIndex >= 0 &&
    sectionIndex < 1024 else {
    @failure.reject("invalid-operation", "Invalid note numbering target")
  }
  let (value, reason) : (Json, String) = try {
    let tree = WordTree::new(self.document())
    let section = self.editable_page_section(tree, target=Some(sectionIndex))
    let settings = self.section_note_settings(tree, section, kind)
    (
      {
        "format": settings.numbering.format,
        "start": settings.numbering.start.to_double(),
        "restart": settings.restart,
      },
      "",
    )
  } catch {
    @failure.Failure(code="invalid-operation", ..) as error => raise error
    @failure.Failure(code="limit-exceeded", ..) as error => raise error
    @failure.Failure(code~, message~, ..) =>
      (Json::null(), code + ":" + message)
  }
  {
    "revision": revision,
    "kind": kind,
    "section": sectionIndex,
    "value": value,
    "reason": reason,
  }
}

///|
/// Changes a section's numbering and preflights the complete candidate layout before commit.
pub fn Session::set_note_numbering(
  self : Session,
  revision : Int,
  kind : String,
  sectionIndex : Int,
  numbering : @layout.PageNumbering,
  restart : String,
  probe~ : @layout.TextProbe,
  profile~ : Map[String, String],
  images~ : @layout.Images,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  guard ["footnote", "endnote"].contains(kind) &&
    sectionIndex >= 0 &&
    sectionIndex < 1024 &&
    (
      ["continuous", "eachSect"].contains(restart) ||
      (kind == "footnote" && restart == "eachPage")
    ) else {
    @failure.reject(
      "invalid-operation", "Invalid note numbering target or restart",
    )
  }
  numbering.validate()
  let original = self.document()
  let tree = WordTree::new(original)
  let section = self.editable_page_section(tree, target=Some(sectionIndex))
  let previous = self.section_note_settings(tree, section, kind)
  let changes = [
    ("numFmt", numbering.format, numbering.format != previous.numbering.format),
    (
      "numStart",
      numbering.start.to_string(),
      numbering.start != previous.numbering.start,
    ),
    ("numRestart", restart, restart != previous.restart),
  ]
  if changes.all(change => !change.2) {
    return self.edit_state()
  }
  let (initial, edits, section) = page_section(original, tree, section)
  let mut candidate = initial
  let tree = WordTree::new(candidate)
  if tree.child(section, kind + "Pr") is None {
    let (updated, edit) = candidate.edit_source([
      tree.new_note_properties(section, kind, ""),
    ])
    candidate = updated
    edits.push(edit)
  }
  let order = ["pos", "numFmt", "numStart", "numRestart"]
  for index, (name, value, changed) in changes {
    if !changed {
      continue
    }
    let tree = WordTree::new(candidate)
    let properties = tree.child(section, kind + "Pr").unwrap()
    let target = tree.child(properties, name)
    let markup = property_markup(
      tree,
      candidate,
      target,
      name,
      Some({ "val": Some(value) }),
    )
    let change : @xml.SourceChange? = if target is None &&
      !tree.nodes[properties].empty {
      let previous = tree.children[properties]
        .filter(id => {
          tree.nodes[id].uri == word_uri &&
          order[:index + 1].contains(tree.nodes[id].name)
        })
        .last()
      let parent = tree.nodes[properties]
      Some({
        node: properties,
        offset: previous
        .map(id => tree.nodes[id].end)
        .unwrap_or(parent.opening_end) -
        parent.start,
        length: 0,
        xml: markup,
      })
    } else {
      properties_change(tree, candidate, properties, name, markup)
    }
    if change is Some(change) {
      let (updated, edit) = candidate.edit_source([change])
      candidate = updated
      edits.push(edit)
    }
  }
  self.commit_running(
    candidate,
    edits,
    self.parts.copy(),
    Map([]),
    Map([]),
    probe~,
    profile~,
    images~,
  )
}
