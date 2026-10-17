///|
/// Enables independent first/even stories without rewriting their stored content.
pub fn Session::set_running_options(
  self : Session,
  revision : Int,
  first : Bool,
  even : Bool,
  probe~ : @layout.TextProbe,
  profile~ : Map[String, String],
  images~ : @layout.Images,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let original = self.document()
  let tree = WordTree::new(original)
  let section = self.editable_page_section(tree)
  let (old_first, old_even) = self.running_options(tree, section)
  if old_first == first && old_even == even {
    return self.edit_state()
  }
  let (initial, edits, section) = page_section(original, tree, section)
  let mut candidate = initial
  if old_first != first {
    let tree = WordTree::new(candidate)
    let markup = if first { "<w:titlePg xmlns:w=\"\{word_uri}\"/>" } else { "" }
    let change : @xml.SourceChange? = if first &&
      tree.child(section, "titlePg") is None &&
      !tree.nodes[section].empty {
      let earlier = [
        "headerReference", "footerReference", "footnotePr", "endnotePr", "type",
        "pgSz", "pgMar", "paperSrc", "pgBorders", "lnNumType", "pgNumType", "cols",
        "formProt", "vAlign", "noEndnote",
      ]
      let node = tree.nodes[section]
      let previous = tree.children[section]
        .filter(id => earlier.contains(tree.nodes[id].name))
        .last()
      Some({
        node: section,
        offset: previous
        .map(id => tree.nodes[id].end)
        .unwrap_or(node.opening_end) -
        node.start,
        length: 0,
        xml: markup,
      })
    } else {
      properties_change(tree, candidate, section, "titlePg", markup)
    }
    if change is Some(change) {
      let (updated, edit) = candidate.edit_source([change])
      candidate = updated
      edits.push(edit)
    }
  }
  let parts = self.parts.copy()
  let part_edits : Map[String, Array[@xml.Edit]] = Map([])
  let created : Map[String, @xml.Document] = Map([])
  if old_even != even {
    let existing = self.settings_part()
    let part = existing.unwrap_or_else(() => {
      self.new_word_part("settings", parts, part_edits, created)
    })
    let document = parts.get(part).unwrap_or_else(() => self.part_xml(part))
    let tree = WordTree::new(document)
    let markup = if even {
      "<w:evenAndOddHeaders xmlns:w=\"\{word_uri}\"/>"
    } else {
      ""
    }
    let change : @xml.SourceChange? = if even &&
      tree.child(0, "evenAndOddHeaders") is None &&
      !tree.nodes[0].empty {
      let earlier = [
        "writeProtection", "view", "zoom", "removePersonalInformation", "removeDateAndTime",
        "doNotDisplayPageBoundaries", "displayBackgroundShape", "printPostScriptOverText",
        "printFractionalCharacterWidth", "printFormsData", "embedTrueTypeFonts",
        "embedSystemFonts", "saveSubsetFonts", "saveFormsData", "mirrorMargins",
        "alignBordersAndEdges", "bordersDoNotSurroundHeader", "bordersDoNotSurroundFooter",
        "gutterAtTop", "hideSpellingErrors", "hideGrammaticalErrors", "activeWritingStyle",
        "proofState", "formsDesign", "attachedTemplate", "linkStyles", "stylePaneFormatFilter",
        "stylePaneSortMethod", "documentType", "mailMerge", "revisionView", "trackRevisions",
        "doNotTrackMoves", "doNotTrackFormatting", "documentProtection", "autoFormatOverride",
        "styleLockTheme", "styleLockQFSet", "defaultTabStop", "autoHyphenation",
        "consecutiveHyphenLimit", "hyphenationZone", "doNotHyphenateCaps", "showEnvelope",
        "summaryLength", "clickAndTypeStyle", "defaultTableStyle",
      ]
      let previous = tree.children[0]
        .filter(id => earlier.contains(tree.nodes[id].name))
        .last()
      let root = tree.nodes[0]
      Some({
        node: 0,
        offset: previous
        .map(id => tree.nodes[id].end)
        .unwrap_or(root.opening_end) -
        root.start,
        length: 0,
        xml: markup,
      })
    } else {
      properties_change(tree, document, 0, "evenAndOddHeaders", markup)
    }
    if change is Some(change) {
      let (updated, edit) = document.edit_source([change])
      parts[part] = updated
      if existing is None {
        created[part] = updated
      } else {
        part_edits[part] = [edit]
      }
    }
  }
  self.commit_running(
    candidate,
    edits,
    parts,
    part_edits,
    created,
    probe~,
    profile~,
    images~,
  )
}

///|
fn Session::commit_running(
  self : Session,
  candidate : @xml.Document,
  edits : Array[@xml.Edit],
  parts : Map[String, @xml.Document],
  part_edits : Map[String, Array[@xml.Edit]],
  created : Map[String, @xml.Document],
  probe~ : @layout.TextProbe,
  profile~ : Map[String, String],
  images~ : @layout.Images,
) -> Json raise @failure.Failure {
  let view = { ..self, parts, }
  let flow = view.flow_from(candidate)
  ignore(@layout.paginate(probe, flow, profile, images))
  let updated = WordTree::new(candidate)
  let paragraphs = updated.order.filter(id => {
    updated.nodes[id].uri == word_uri && updated.nodes[id].name == "p"
  })
  let mut bytes = xml_part_edit_bytes(part_edits, created)
  for edit in edits {
    let count = edit_bytes(edit)
    guard count <= history_byte_limit - bytes else {
      @failure.reject("limit-exceeded", "Running area exceeds history budget")
    }
    bytes += count
  }
  let pending = self.typing_format
  self.commit_edit(
    {
      xml: edits,
      parts: part_edits,
      created,
      created_media: Map([]),
      before: self.selection,
      after: self.selection.map(s => s.without_visual_hints()),
      paragraphs,
      bytes,
    },
    candidate,
    parts~,
  )
  self.typing_format = pending
  self.edit_result(paragraphs)
}
