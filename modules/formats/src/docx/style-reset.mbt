///|
priv enum StyleResetProfile {
  Plain
  Bold
  Italic
  Heading(Int32)
  Preset(String, String)
}

///|
fn Styles::reset_profile(self : Styles, key : String) -> StyleResetProfile? {
  guard self.tree is Some(tree) && self.ids.get(key) is Some(id) else {
    return None
  }
  let node = tree.nodes[id]
  let kind = node.attribute("type", uri=word_uri).unwrap_or("paragraph")
  guard ["paragraph", "character"].contains(kind) else { return None }
  if ["1", "true", "on"].contains(
      node.attribute("default", uri=word_uri).unwrap_or("0"),
    ) {
    return Some(Plain)
  }
  if ["1", "true", "on"].contains(
      node.attribute("customStyle", uri=word_uri).unwrap_or("0"),
    ) {
    return None
  }
  let name = tree.value(id, "name").unwrap_or(key)
  if kind == "paragraph" && (key == "Normal" || name == "Normal") {
    return Some(Plain)
  }
  if kind == "paragraph" {
    let name = name.to_lower()
    for level in 1..<=9 {
      if key == "Heading\{level}" || name == "heading \{level}" {
        return Some(Heading(level))
      }
    }
  }
  if kind == "character" {
    if key == "DefaultParagraphFont" || name == "Default Paragraph Font" {
      return Some(Plain)
    }
    if key == "Emphasis" || name == "Emphasis" {
      return Some(Italic)
    }
    if key == "Strong" || name == "Strong" {
      return Some(Bold)
    }
  }
  builtin_style_properties(key, name, kind, self.themes).map(p => {
    Preset(p.0, p.1)
  })
}

///|
fn Styles::default_style(
  self : Styles,
  kind : String,
) -> String? raise @failure.Failure {
  let tree = self.tree.unwrap()
  let defaults = self.ids
    .keys()
    .filter(key => {
      let node = tree.nodes[self.ids[key]]
      node.attribute("type", uri=word_uri).unwrap_or("paragraph") == kind &&
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
      node.attribute("type", uri=word_uri).unwrap_or("paragraph") == kind &&
      (
        key ==
        (if kind == "paragraph" { "Normal" } else { "DefaultParagraphFont" }) ||
        tree.value(node.id, "name") ==
        Some(
          if kind == "paragraph" {
            "Normal"
          } else {
            "Default Paragraph Font"
          },
        )
      )
    })
    .to_array()
  }
  guard choices.length() <= 1 else {
    @failure.reject("invalid-style", "Ambiguous default \{kind} style")
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
  let base = match profile {
    Plain => None
    _ => styles.default_style(kind)
  }
  let (paragraph, character) = match profile {
    Plain => ("", "")
    Bold => ("", "<od:rPr xmlns:od=\"\{word_uri}\"><od:b/><od:bCs/></od:rPr>")
    Italic => ("", "<od:rPr xmlns:od=\"\{word_uri}\"><od:i/><od:iCs/></od:rPr>")
    Heading(level) => heading_style_properties(level)
    Preset(paragraph, character) => (paragraph, character)
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
    } else if field == "pPr" {
      paragraph
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
