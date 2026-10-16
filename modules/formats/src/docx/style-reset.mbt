///|
fn Styles::reset_profile(self : Styles, key : String) -> String? {
  guard self.tree is Some(tree) && self.ids.get(key) is Some(id) else {
    return None
  }
  let node = tree.nodes[id]
  let kind = node.attribute("type", uri=word_uri).unwrap_or("paragraph")
  guard ["paragraph", "character"].contains(kind) else { return None }
  if ["1", "true", "on"].contains(
      node.attribute("default", uri=word_uri).unwrap_or("0"),
    ) {
    return Some("plain")
  }
  if ["1", "true", "on"].contains(
      node.attribute("customStyle", uri=word_uri).unwrap_or("0"),
    ) {
    return None
  }
  let name = tree.value(id, "name").unwrap_or(key)
  if kind == "paragraph" && (key == "Normal" || name == "Normal") {
    return Some("plain")
  }
  if kind == "character" {
    if key == "DefaultParagraphFont" || name == "Default Paragraph Font" {
      return Some("plain")
    }
    if key == "Emphasis" || name == "Emphasis" {
      return Some("italic")
    }
    if key == "Strong" || name == "Strong" {
      return Some("bold")
    }
  }
  None
}

///|
fn Styles::default_character_style(
  self : Styles,
) -> String? raise @failure.Failure {
  let tree = self.tree.unwrap()
  let defaults = self.ids
    .keys()
    .filter(key => {
      let node = tree.nodes[self.ids[key]]
      node.attribute("type", uri=word_uri) == Some("character") &&
      ["1", "true", "on"].contains(
        node.attribute("default", uri=word_uri).unwrap_or("0"),
      )
    })
    .to_array()
  let choices = if !defaults.is_empty() {
    defaults
  } else {
    self.ids
    .keys()
    .filter(key => {
      let node = tree.nodes[self.ids[key]]
      node.attribute("type", uri=word_uri) == Some("character") &&
      (
        key == "DefaultParagraphFont" ||
        tree.value(node.id, "name") == Some("Default Paragraph Font")
      )
    })
    .to_array()
  }
  guard choices.length() <= 1 else {
    @failure.reject("invalid-style", "Ambiguous default character style")
  }
  choices.get(0)
}

///|
fn Session::reset_style_format(
  self : Session,
  key : String,
) -> Json raise @failure.Failure {
  let styles = self.styles([])
  guard styles.tree is Some(tree) &&
    styles.ids.get(key) is Some(id) &&
    styles.reset_profile(key) is Some(profile) else {
    @failure.reject(
      "protected-content", "This style has no supported reset profile",
    )
  }
  let kind = tree.nodes[id]
    .attribute("type", uri=word_uri)
    .unwrap_or("paragraph")
  styles.validate_style(key, kind)
  guard styles.paragraph.readOnlyReason.is_empty() else {
    @failure.reject("protected-content", styles.paragraph.readOnlyReason)
  }
  let base = if profile == "plain" {
    None
  } else {
    styles.default_character_style()
  }
  let character = if profile == "bold" {
    "<od:rPr xmlns:od=\"\{word_uri}\"><od:b/><od:bCs/></od:rPr>"
  } else if profile == "italic" {
    "<od:rPr xmlns:od=\"\{word_uri}\"><od:i/><od:iCs/></od:rPr>"
  } else {
    ""
  }
  let mut candidate = self.part_xml(styles.part)
  let edits : Array[@xml.Edit] = []
  let mut bytes = 0
  for (field, value) in [("basedOn", base), ("pPr", None), ("rPr", None)] {
    let tree = WordTree::new(candidate)
    let markup = if field == "basedOn" {
      property_markup(
        tree,
        candidate,
        tree.child(id, field),
        field,
        value.map(value => Map::from_array([("val", Some(value))])),
      )
    } else if field == "rPr" {
      character
    } else {
      ""
    }
    if tree.child(id, field) is Some(node) {
      let node = tree.nodes[node]
      let source = candidate.source()[node.start:node.end]
      guard source == markup ||
        (!source.contains("<!--") && !source.contains("<?")) else {
        @failure.reject(
          "protected-content", "Unknown style property markup prevents reset",
        )
      }
    }
    if style_property_change(tree, candidate, id, field, markup) is Some(change) {
      let (updated, edit) = candidate.edit_source([change])
      let count = edit_bytes(edit)
      guard count <= history_byte_limit - bytes else {
        @failure.reject("limit-exceeded", "Style reset exceeds history budget")
      }
      candidate = updated
      edits.push(edit)
      bytes += count
    }
  }
  if edits.is_empty() {
    return self.edit_state()
  }
  let parts = self.parts.copy()
  parts[styles.part] = candidate
  let view = { ..self, parts, }
  let updated = view.styles([])
  updated.validate_style(key, kind)
  let affected = self.validate_style_transition(
    styles,
    updated,
    self.document(),
    parts~,
  )
  let pending = self.typing_format
  self.commit_edit(
    {
      xml: [],
      parts: Map::from_array([(styles.part, edits)]),
      created: Map([]),
      created_media: Map([]),
      before: self.selection,
      after: self.selection.map(s => s.without_visual_hints()),
      paragraphs: affected,
      bytes,
    },
    self.document(),
    parts~,
  )
  self.typing_format = pending
  self.edit_result(affected)
}
