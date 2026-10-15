///|
fn Styles::validate_paragraph_style(
  self : Styles,
  key : String,
) -> Unit raise @failure.Failure {
  guard !key.is_empty() &&
    key.length() <= 200 &&
    @xml.valid_text(key) &&
    self.tree is Some(tree) &&
    self.ids.contains(key) else {
    @failure.reject("invalid-style", "Unknown paragraph style: " + key)
  }
  let diagnostics : Array[String] = []
  let chain = self.chain(key, diagnostics)
  for id in chain {
    guard tree.nodes[id].attribute("type", uri=word_uri).unwrap_or("paragraph") ==
      "paragraph" else {
      @failure.reject(
        "invalid-style", "A paragraph style cannot inherit a different style type",
      )
    }
  }
  guard diagnostics.is_empty() else {
    @failure.reject("protected-content", diagnostics[0])
  }
  let paragraph = self.paragraph_style(tree, self.ids[key], [], style=Set(key))
  ignore(
    ParagraphFormat::new(
      align=Set(paragraph.align),
      before=Set(paragraph.before),
      after=Set(paragraph.after),
      left=Set(paragraph.left),
      right=Set(paragraph.right),
      first=Set(paragraph.first),
      line=Set(paragraph.line),
      tabs=Set(paragraph.tabs),
    ).properties(),
  )
  let mut character = self.defaults
  for id in chain {
    if tree.child(id, "rPr") is Some(properties) {
      character = run_properties(
        tree,
        properties,
        character,
        self.themes,
        inherited=true,
      )
    }
  }
  CharacterFormat::new(
    family=Set(character.family),
    size=Set(character.size),
    color=Set(character.color),
    bold=Set(character.bold),
    italic=Set(character.italic),
    underline=Set(character.underline),
    strike=Set(character.strike),
    highlight=Set(character.highlight),
    vertAlign=Set(character.vertAlign),
  ).validate()
}

///|
/// Lists existing paragraph styles without changing document state.
pub fn Session::paragraph_styles(
  self : Session,
  revision : Int,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let styles = self.styles([])
  let result : Array[Json] = []
  let mut truncated = false
  if styles.tree is Some(tree) {
    for id in tree.order {
      let node = tree.nodes[id]
      if node.uri != word_uri ||
        node.name != "style" ||
        node.parent != 0 ||
        node.attribute("type", uri=word_uri).unwrap_or("paragraph") !=
        "paragraph" {
        continue
      }
      guard node.attribute("styleId", uri=word_uri) is Some(key) else {
        continue
      }
      if result.length() == 1024 {
        truncated = true
        break
      }
      let reason = try {
        styles.validate_paragraph_style(key)
        ""
      } catch {
        @failure.Failure(message~, ..) => message
      }
      result.push({
        "id": key,
        "name": tree.value(id, "name").unwrap_or(key),
        "reason": reason,
      })
    }
  }
  { "revision": revision, "styles": Json(result), "truncated": truncated }
}
