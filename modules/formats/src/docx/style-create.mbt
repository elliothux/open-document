///|
/// Creates a custom style derived from an existing supported style; returns its stable id and state.
pub fn Session::create_style(
  self : Session,
  revision : Int,
  name : String,
  based_on : String,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  guard !name.trim().is_empty() && name.length() <= 200 && @xml.valid_text(name) else {
    @failure.reject("invalid-operation", "Invalid style name")
  }
  let styles = self.styles([])
  guard styles.ids.length() < 4096 else {
    @failure.reject("limit-exceeded", "Too many styles")
  }
  guard styles.tree is Some(tree) && styles.ids.get(based_on) is Some(base) else {
    @failure.reject("invalid-style", "Choose an existing base style")
  }
  let kind = tree.nodes[base]
    .attribute("type", uri=word_uri)
    .unwrap_or("paragraph")
  guard ["paragraph", "character"].contains(kind) else {
    @failure.reject("invalid-style", "Unsupported style type")
  }
  styles.validate_style(based_on, kind)
  for id in styles.ids.values() {
    guard tree.nodes[id].attribute("type", uri=word_uri).unwrap_or("paragraph") !=
      kind ||
      tree
      .value(id, "name")
      .unwrap_or(tree.nodes[id].attribute("styleId", uri=word_uri).unwrap()) !=
      name else {
      @failure.reject("invalid-style", "A style with this name already exists")
    }
  }
  let reserved : Map[String, Bool] = Map([])
  for part in self.style_part_names() {
    for node in self.part_xml(part).nodes() {
      let key = if node.name == "style" {
        node.attribute("styleId", uri=word_uri)
      } else if style_reference_names.contains(node.name) {
        node.attribute("val", uri=word_uri)
      } else {
        None
      }
      if node.uri == word_uri &&
        key is Some(key) &&
        key.length() <= 32 &&
        key.has_prefix("odStyle") {
        reserved[key] = true
      }
    }
  }
  let key = for i = 1; i <= 65536; i = i + 1 {
    let key = "odStyle\{i}"
    if !styles.ids.contains(key) && !reserved.contains(key) {
      break key
    }
  } nobreak {
    @failure.reject("limit-exceeded", "No free style identity")
  }
  let markup = "<od:style xmlns:od=\"\{word_uri}\" od:type=\"\{kind}\" od:customStyle=\"1\" od:styleId=\"\{key}\"><od:name od:val=\"" +
    property_attribute(name) +
    "\"/><od:basedOn od:val=\"" +
    property_attribute(based_on) +
    "\"/></od:style>"
  let document = self.part_xml(styles.part)
  let root = document.nodes()[0]
  let (candidate, edit) = document.edit_source([
    {
      node: root.id,
      offset: root.closing_start - root.start,
      length: 0,
      xml: markup,
    },
  ])
  let parts = self.parts.copy()
  parts[styles.part] = candidate
  let view = { ..self, parts, }
  let updated = view.styles([])
  updated.validate_style(key, kind)
  let affected = self.validate_style_transition(
    styles,
    updated,
    self.document(),
  )
  let pending = self.typing_format
  self.commit_edit(
    {
      xml: [],
      parts: Map::from_array([(styles.part, [edit])]),
      before: self.selection,
      after: self.selection,
      paragraphs: affected,
      bytes: edit_bytes(edit),
    },
    self.document(),
    parts~,
  )
  self.typing_format = pending
  { "id": key, "state": self.edit_state() }
}
