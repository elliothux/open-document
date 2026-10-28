///|
fn Session::endnote_position_settings(
  self : Session,
) -> Json raise @failure.Failure {
  try {
    self.check_document_protection()
    { "position": self.note_settings("endnote").position, "reason": "" }
  } catch {
    @failure.Failure(code="limit-exceeded", ..) as error => raise error
    @failure.Failure(code~, message~, ..) =>
      { "position": Json::null(), "reason": code + ":" + message }
  }
}

///|
/// Moves all endnotes to document or section ends, preserving numbering and note content.
pub fn Session::set_endnote_position(
  self : Session,
  revision : Int32,
  position : String,
  probe~ : @layout.TextProbe,
  profile~ : Map[String, String],
  images~ : @layout.Images,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  guard ["docEnd", "sectEnd"].contains(position) else {
    @failure.reject("invalid-operation", "Invalid endnote placement")
  }
  self.check_document_protection()
  if self.note_settings("endnote").position == position {
    return self.edit_state()
  }
  let parts = self.parts.copy()
  let edits : Map[String, Array[@xml.Edit]] = Map([])
  let created : Map[String, @xml.Document] = Map([])
  let existing = self.settings_part()
  let part = existing.unwrap_or_else(() => {
    self.new_word_part("settings", parts, edits, created)
  })
  let document = parts.get(part).unwrap_or_else(() => self.part_xml(part))
  let tree = WordTree::new(document)
  let change = if tree.child(0, "endnotePr") is Some(properties) {
    properties_change(
      tree,
      document,
      properties,
      "pos",
      property_markup(
        tree,
        document,
        tree.child(properties, "pos"),
        "pos",
        Some({ "val": Some(position) }),
      ),
    )
  } else {
    let markup = "<od:endnotePr xmlns:od='\{word_uri}'><od:pos od:val='\{position}'/></od:endnotePr>"
    // Settings place note properties immediately before compatibility and later settings.
    let later = [
      "compat", "docVars", "rsids", "mathPr", "uiCompat97To2003", "attachedSchema",
      "themeFontLang", "clrSchemeMapping", "doNotIncludeSubdocsInStats", "doNotAutoCompressPictures",
      "forceUpgrade", "captions", "readModeInkLockDown", "smartTagType", "schemaLibrary",
      "shapeDefaults", "doNotEmbedSmartTags", "decimalSymbol", "listSeparator",
    ]
    let next = tree.children[0]
      .iter()
      .find_first(id => {
        tree.nodes[id].uri == word_uri && later.contains(tree.nodes[id].name)
      })
    if !tree.nodes[0].empty && next is Some(id) {
      Some({
        node: 0,
        offset: tree.nodes[id].start - tree.nodes[0].start,
        length: 0,
        xml: markup,
      })
    } else if tree.nodes[0].empty {
      properties_change(tree, document, 0, "endnotePr", markup)
    } else {
      Some({
        node: 0,
        offset: tree.nodes[0].closing_start - tree.nodes[0].start,
        length: 0,
        xml: markup,
      })
    }
  }
  guard change is Some(change) else { return self.edit_state() }
  let (candidate, edit) = document.edit_source([change])
  parts[part] = candidate
  if existing is None {
    created[part] = candidate
  } else {
    edits[part] = [edit]
  }
  self.commit_running(
    self.document(),
    [],
    parts,
    edits,
    created,
    probe~,
    profile~,
    images~,
  )
}
