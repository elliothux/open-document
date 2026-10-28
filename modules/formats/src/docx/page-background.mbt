///|
fn WordTree::page_background(self : WordTree) -> String? raise @failure.Failure {
  let nodes = self.children[0].filter(id => {
    self.nodes[id].uri == word_uri && self.nodes[id].name == "background"
  })
  guard nodes.length() <= 1 else {
    @failure.reject("protected-content", "Duplicate page backgrounds")
  }
  guard nodes.get(0) is Some(id) else { return None }
  let node = self.nodes[id]
  let source = self.source[node.start:node.end]
  guard self.children[id].is_empty() &&
    node.text.trim().is_empty() &&
    node.attributes.all(a => a.uri == word_uri && a.name == "color") &&
    !source.contains("<!--") &&
    !source.contains("<?") else {
    @failure.reject(
      "protected-content", "Extended page background is protected",
    )
  }
  let color = node.attribute("color", uri=word_uri).unwrap_or("auto")
  if color == "auto" {
    return None
  }
  guard color.length() == 6 && color.iter().all(c => c.is_ascii_hexdigit()) else {
    @failure.reject("invalid-style", "Invalid page background color")
  }
  Some(color.to_lower())
}

///|
fn Session::page_background_query(
  self : Session,
  tree : WordTree,
) -> Json raise @failure.Failure {
  let reason = self.theme_edit_reason()
  if !reason.is_empty() {
    return { "color": Json::null(), "reason": reason }
  }
  {
    "color": tree.page_background().map(c => Json(c)).unwrap_or(Json::null()),
    "reason": "",
  } catch {
    @failure.Failure(message~, ..) =>
      { "color": Json::null(), "reason": message }
  }
}

///|
/// Sets a solid document background, or removes it for the default white page.
pub fn Session::set_page_background(
  self : Session,
  revision : Int32,
  color : String?,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  if color is Some(color) {
    guard color.length() == 6 && color.iter().all(c => c.is_ascii_hexdigit()) else {
      @failure.reject(
        "invalid-operation", "Page background requires six RGB digits or null",
      )
    }
  }
  let color = color.map(c => c.to_lower())
  let document = self.document()
  let tree = WordTree::new(document)
  let old = tree.page_background()
  if old == color && (color is Some(_) || tree.child(0, "background") is None) {
    return self.edit_state()
  }
  let reason = self.theme_edit_reason()
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let target = tree.child(0, "background")
  let markup = color
    .map(c => "<w:background xmlns:w=\"\{word_uri}\" w:color=\"\{c}\"/>")
    .unwrap_or("")
  let change : @xml.SourceChange = if target is Some(id) {
    {
      node: 0,
      offset: tree.nodes[id].start - tree.nodes[0].start,
      length: tree.nodes[id].end - tree.nodes[id].start,
      xml: markup,
    }
  } else {
    {
      node: 0,
      offset: tree.nodes[0].opening_end - tree.nodes[0].start,
      length: 0,
      xml: markup,
    }
  }
  let (candidate, edit) = document.edit_source([change])
  let paragraphs = tree.order.filter(id => {
    tree.nodes[id].uri == word_uri && tree.nodes[id].name == "p"
  })
  let pending = self.typing_format
  self.commit_edit(
    {
      xml: [edit],
      parts: Map([]),
      created: Map([]),
      created_media: Map([]),
      before: self.selection,
      after: self.selection.map(s => s.without_visual_hints()),
      paragraphs,
      bytes: edit_bytes(edit),
    },
    candidate,
  )
  self.typing_format = pending
  self.edit_result(paragraphs)
}
