///|
fn Styles::inherited_style(
  self : Styles,
  key : String,
) -> (RunStyle, @layout.Paragraph, Map[String, Bool]) raise @failure.Failure {
  let tree = self.tree.unwrap()
  let complex = { "bCs": false, "iCs": false }
  if tree
    .child(0, "docDefaults")
    .bind(id => tree.child(id, "rPrDefault"))
    .bind(id => tree.child(id, "rPr"))
    is Some(id) {
    for name, value in complex.copy() {
      complex[name] = tree.character_toggle(id, name, value, false)
    }
  }
  let mut character = self.defaults
  let mut paragraph = self.paragraph
  let chain = self.chain(key, [])
  for id in chain[:chain.length() - 1] {
    if tree.child(id, "rPr") is Some(properties) {
      character = run_properties(
        tree,
        properties,
        character,
        self.themes,
        inherited=true,
      )
      for name, value in complex.copy() {
        complex[name] = tree.character_toggle(properties, name, value, true)
      }
    }
    if tree.child(id, "pPr") is Some(properties) {
      paragraph = paragraph_properties(tree, properties, paragraph)
    }
  }
  (character, paragraph, complex)
}

///|
fn style_toggle(
  change : FormatChange[Bool],
  inherited : Bool,
) -> FormatChange[Bool] {
  match change {
    Set(value) => Set(value != inherited)
    _ => change
  }
}

///|
fn style_property_change(
  tree : WordTree,
  document : @xml.Document,
  id : Int,
  field : String,
  markup : String,
) -> @xml.SourceChange? {
  let parent = tree.nodes[id]
  if tree.child(id, field) is Some(_) || parent.empty || markup.is_empty() {
    return properties_change(tree, document, id, field, markup)
  }
  let later = if field == "basedOn" {
    [
      "next", "link", "autoRedefine", "hidden", "uiPriority", "semiHidden", "unhideWhenUsed",
      "qFormat", "locked", "personal", "personalCompose", "personalReply", "rsid",
      "pPr", "rPr", "tblPr", "trPr", "tcPr", "tblStylePr",
    ]
  } else if field == "pPr" {
    ["rPr", "tblPr", "trPr", "tcPr", "tblStylePr"]
  } else {
    ["tblPr", "trPr", "tcPr", "tblStylePr"]
  }
  let offset = if field == "name" {
    parent.opening_end
  } else {
    tree.children[id]
    .iter()
    .find_first(child => later.contains(tree.nodes[child].name))
    .map(child => tree.nodes[child].start)
    .unwrap_or(parent.closing_start)
  }
  Some({ node: id, offset: offset - parent.start, length: 0, xml: markup, })
}

///|
/// Updates an existing style's name, inheritance or supported properties as one edit.
/// Boolean values describe the style's effective value above its basedOn chain.
pub fn Session::update_style(
  self : Session,
  revision : Int,
  key : String,
  character : CharacterFormat,
  paragraph : ParagraphFormat,
  name~ : String? = None,
  based_on~ : FormatChange[String] = Keep,
  reset~ : Bool = false,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  if reset {
    guard name is None &&
      based_on is Keep &&
      character.style is Keep &&
      paragraph.style is Keep &&
      character.properties().is_empty() &&
      paragraph.properties().is_empty() &&
      paragraph.tabs is Keep else {
      @failure.reject(
        "invalid-operation", "Style reset cannot include other changes",
      )
    }
    return self.reset_style_format(key)
  }
  guard character.style is Keep && paragraph.style is Keep else {
    @failure.reject(
      "invalid-operation", "Style updates cannot change style references",
    )
  }
  character.validate()
  let paragraph_patch = paragraph.properties()
  let styles = self.styles([])
  guard styles.ids.length() <= 4096 else {
    @failure.reject(
      "limit-exceeded", "Too many styles for a shared style update",
    )
  }
  guard styles.tree is Some(tree) && styles.ids.get(key) is Some(id) else {
    @failure.reject("invalid-style", "Unknown style: " + key)
  }
  let kind = tree.nodes[id]
    .attribute("type", uri=word_uri)
    .unwrap_or("paragraph")
  guard ["paragraph", "character"].contains(kind) else {
    @failure.reject("invalid-style", "Unsupported style type")
  }
  styles.validate_style(key, kind)
  guard styles.paragraph.readOnlyReason.is_empty() else {
    @failure.reject("protected-content", styles.paragraph.readOnlyReason)
  }
  guard kind == "paragraph" ||
    (paragraph_patch.is_empty() && paragraph.tabs is Keep) else {
    @failure.reject(
      "invalid-operation", "Character styles cannot define paragraph properties",
    )
  }
  for field in ["name", "basedOn", "rPr", "pPr"] {
    guard tree.children[id]
      .filter(child => {
        tree.nodes[child].uri == word_uri && tree.nodes[child].name == field
      })
      .length() <=
      1 else {
      @failure.reject("protected-content", "Duplicate style property: " + field)
    }
    if ["rPr", "pPr"].contains(field) &&
      tree.child(id, field) is Some(properties) {
      tree.check_structure_properties(properties)
    }
  }
  if name is Some(name) {
    guard !name.trim().is_empty() &&
      name.length() <= 200 &&
      @xml.valid_text(name) else {
      @failure.reject("invalid-operation", "Invalid style name")
    }
    if tree.child(id, "name") is Some(property) {
      let node = tree.nodes[property]
      guard tree.children[property].is_empty() &&
        node.text.trim().is_empty() &&
        node.attributes.iter().all(a => a.uri == word_uri && a.name == "val") else {
        @failure.reject("protected-content", "Unknown style name markup")
      }
    }
  }
  let mut candidate = self.part_xml(styles.part)
  let edits : Array[@xml.Edit] = []
  let mut bytes = 0
  if !(based_on is Keep) {
    if tree.child(id, "basedOn") is Some(property) {
      let node = tree.nodes[property]
      guard tree.children[property].is_empty() &&
        node.text.trim().is_empty() &&
        node.attributes.iter().all(a => a.uri == word_uri && a.name == "val") else {
        @failure.reject("protected-content", "Unknown style inheritance markup")
      }
    }
    let property = match based_on {
      Set(parent) => {
        styles.validate_style(parent, kind)
        guard !styles.chain(parent, []).contains(id) else {
          @failure.reject(
            "invalid-style", "Style inheritance cannot contain a cycle",
          )
        }
        Some(Map::from_array([("val", Some(parent))]))
      }
      _ => None
    }
    let markup = property_markup(
      tree,
      candidate,
      tree.child(id, "basedOn"),
      "basedOn",
      property,
    )
    if style_property_change(tree, candidate, id, "basedOn", markup)
      is Some(change) {
      let (updated, edit) = candidate.edit_source([change])
      bytes = edit_bytes(edit)
      guard bytes <= history_byte_limit else {
        @failure.reject("limit-exceeded", "Style update exceeds history budget")
      }
      candidate = updated
      edits.push(edit)
    }
  }
  let inherited = { ..styles, tree: Some(WordTree::new(candidate)), }
  let (base, inherited_paragraph, complex) = inherited.inherited_style(key)
  let character_patch = {
    ..character,
    bold: style_toggle(character.bold, base.bold),
    italic: style_toggle(character.italic, base.italic),
    strike: style_toggle(character.strike, base.strike),
  }.properties()
  for (field, change) in [("bCs", character.bold), ("iCs", character.italic)] {
    if change is Set(value) {
      character_patch[field] = Some(
        Map::from_array([
          ("val", Some(if value != complex[field] { "1" } else { "0" })),
        ]),
      )
    }
  }
  let nested = Map([])
  match paragraph.tabs {
    Keep => ()
    Clear => nested["tabs"] = ""
    Set(stops) => nested["tabs"] = tabs_markup(inherited_paragraph.tabs, stops)
  }
  for field in ["name", "rPr", "pPr"] {
    let tree = WordTree::new(candidate)
    let markup = match field {
      "name" =>
        match name {
          None => continue
          Some(value) =>
            property_markup(
              tree,
              candidate,
              tree.child(id, "name"),
              "name",
              Some(Map::from_array([("val", Some(value))])),
            )
        }
      "rPr" => formatted_properties(tree, candidate, id, "rPr", character_patch)
      _ =>
        formatted_properties(
          tree,
          candidate,
          id,
          "pPr",
          paragraph_patch,
          nested~,
        )
    }
    if style_property_change(tree, candidate, id, field, markup) is Some(change) {
      let (updated, edit) = candidate.edit_source([change])
      let count = edit_bytes(edit)
      guard count <= history_byte_limit - bytes else {
        @failure.reject("limit-exceeded", "Style update exceeds history budget")
      }
      candidate = updated
      edits.push(edit)
      bytes += count
    }
  }
  if edits.is_empty() {
    return self.edit_state()
  }
  let updated_styles = { ..styles, tree: Some(WordTree::new(candidate)), }
  updated_styles.validate_style(key, kind)
  let parts = self.parts.copy()
  parts[styles.part] = candidate
  let affected = self.validate_style_transition(
    styles,
    updated_styles,
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
      after: self.selection.map(selection => selection.without_visual_hints()),
      paragraphs: affected,
      bytes,
    },
    self.document(),
    parts~,
  )
  self.typing_format = pending
  self.edit_result(affected)
}
