///|
fn Session::settings_part(self : Session) -> String? raise @failure.Failure {
  let mut part = None
  for rel in self.relationships() {
    if rel.owner != self.main ||
      rel.kind !=
      "http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" {
      continue
    }
    guard !rel.external && part is None else {
      @failure.reject(
        "unsupported-layout", "External or duplicate settings are unsupported",
      )
    }
    let root = self.part_xml(rel.target).nodes()[0]
    guard root.uri == word_uri && root.name == "settings" else {
      @failure.reject("invalid-style", "Invalid settings root", part=rel.target)
    }
    part = Some(rel.target)
  }
  part
}

///|
/// Sets the document's default tab interval in points; None removes the explicit setting.
pub fn Session::set_default_tab_stop(
  self : Session,
  revision : Int,
  interval : Double?,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  if interval is Some(value) {
    guard value >= 0 &&
      value <= 1584 &&
      value * 20 == (value * 20).to_int().to_double() else {
      @failure.reject(
        "invalid-operation", "Default tab interval must be in twips within 1584 points",
      )
    }
  }
  let original = self.settings_part()
  if original is None && interval is None {
    return self.edit_state()
  }
  let parts = self.parts.copy()
  let edits : Map[String, Array[@xml.Edit]] = Map([])
  let created : Map[String, @xml.Document] = Map([])
  let part = match original {
    Some(part) => part
    None => self.new_word_part("settings", parts, edits, created)
  }
  let document = match parts.get(part) {
    Some(document) => document
    None => self.part_xml(part)
  }
  let tree = WordTree::new(document)
  if tree.child(0, "documentProtection") is Some(id) {
    guard !["1", "true", "on"].contains(
      tree.nodes[id].attribute("enforcement", uri=word_uri).unwrap_or("0"),
    ) else {
      @failure.reject("protected-content", "Document settings are protected")
    }
  }
  let targets = tree.children[0].filter(id => {
    tree.nodes[id].uri == word_uri && tree.nodes[id].name == "defaultTabStop"
  })
  guard targets.length() <= 1 else {
    @failure.reject("protected-content", "Duplicate default tab setting")
  }
  let target = targets.get(0)
  if target is Some(id) {
    let node = tree.nodes[id]
    guard tree.children[id].is_empty() &&
      node.text.trim().is_empty() &&
      node.attributes.iter().all(a => a.uri == word_uri && a.name == "val") else {
      @failure.reject("protected-content", "Unknown default tab markup")
    }
  }
  let markup = property_markup(
    tree,
    document,
    target,
    "defaultTabStop",
    interval.map(value => {
      Map::from_array([("val", Some((value * 20).to_int().to_string()))])
    }),
  )
  let change : @xml.SourceChange? = if target is None &&
    !tree.nodes[0].empty &&
    !markup.is_empty() {
    let earlier = [
      "writeProtection", "view", "zoom", "removePersonalInformation", "removeDateAndTime",
      "doNotDisplayPageBoundaries", "displayBackgroundShape", "printPostScriptOverText",
      "printFractionalCharacterWidth", "printFormsData", "embedTrueTypeFonts", "embedSystemFonts",
      "saveSubsetFonts", "saveFormsData", "mirrorMargins", "alignBordersAndEdges",
      "bordersDoNotSurroundHeader", "bordersDoNotSurroundFooter", "gutterAtTop",
      "hideSpellingErrors", "hideGrammaticalErrors", "activeWritingStyle", "proofState",
      "formsDesign", "attachedTemplate", "linkStyles", "stylePaneFormatFilter", "stylePaneSortMethod",
      "documentType", "mailMerge", "revisionView", "trackRevisions", "doNotTrackMoves",
      "doNotTrackFormatting", "documentProtection", "autoFormatOverride", "styleLockTheme",
      "styleLockQFSet",
    ]
    let previous = tree.children[0]
      .iter()
      .filter(id => {
        tree.nodes[id].uri == word_uri && earlier.contains(tree.nodes[id].name)
      })
      .last()
    Some({
      node: 0,
      offset: previous
      .map(id => tree.nodes[id].end)
      .unwrap_or(tree.nodes[0].opening_end) -
      tree.nodes[0].start,
      length: 0,
      xml: markup,
    })
  } else {
    properties_change(tree, document, 0, "defaultTabStop", markup)
  }
  guard change is Some(change) else { return self.edit_state() }
  let (candidate, edit) = document.edit_source([change])
  parts[part] = candidate
  if created.contains(part) {
    created[part] = candidate
  } else {
    edits[part] = [edit]
  }
  let bytes = xml_part_edit_bytes(edits, created)
  let view = { ..self, parts, }
  ignore(view.default_tab())
  let body = WordTree::new(self.document())
  let paragraphs = body.order.filter(id => {
    let node = body.nodes[id]
    node.uri == word_uri && node.name == "p"
  })
  let pending = self.typing_format
  self.commit_edit(
    {
      xml: [],
      parts: edits,
      created,
      created_media: Map([]),
      before: self.selection,
      after: self.selection.map(selection => selection.without_visual_hints()),
      paragraphs,
      bytes,
    },
    self.document(),
    parts~,
  )
  self.typing_format = pending
  self.edit_result(paragraphs)
}
