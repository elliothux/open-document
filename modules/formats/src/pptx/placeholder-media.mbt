///|
fn Session::media_fill_reason(self : Session, object : Object) -> String {
  let reason = self.empty_placeholder_reason(object, ["media", "obj"])
  if !reason.is_empty() {
    return reason
  }
  if self.source_view is Some(_) {
    return "Fill media placeholders in the slide view"
  }
  try {
    let nv = object.source.child("nvSpPr", uri=presentation_uri).unwrap()
    let common = nv.child("cNvPr", uri=presentation_uri).unwrap()
    let application = nv.child("nvPr", uri=presentation_uri).unwrap()
    if common.child("hlinkClick") is Some(_) ||
      !application.node.attributes.is_empty() ||
      !application.tree.children
      .get(application.node.id)
      .unwrap_or([])
      .all(node => node.uri == presentation_uri && node.name == "ph") {
      return "Existing placeholder actions or media metadata are protected"
    }
    ""
  } catch {
    @failure.Failure(message~, ..) => message
  }
}

///|
fn Session::selected_media_placeholder(
  self : Session,
) -> Object raise @failure.Failure {
  guard self.selection.mode == "object" && self.selection.objects.length() == 1 else {
    @failure.reject("invalid-operation", "Select one media placeholder")
  }
  let object = self.current().object(self.selection.object)
  let reason = self.media_fill_reason(object)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  object
}

///|
fn media_picture_markup(
  markup : String,
  kind : String,
  link : String,
  budget : @archive.Budget,
) -> String raise @failure.Failure {
  let document = @xml.Document::parse(
    @utf8.encode(markup),
    "media-picture",
    budget.xml_depth,
    budget.entry_bytes,
  )
  let tree = Tree::new("media-picture", document)
  let picture : Ref = { tree, node: tree.nodes[0], }
  let nv = picture.child("nvPicPr", uri=presentation_uri).unwrap()
  let common = nv.child("cNvPr", uri=presentation_uri).unwrap()
  let click = "<a:hlinkClick xmlns:a=\"\{drawing_uri}\" xmlns:r=\"\{relationship_uri}\" r:id=\"\" action=\"ppaction://media\"/>"
  document.edit_source([
    paint_child_change(common, None, click, ["hlinkMouseOver", "extLst"]),
    insertion(
      nv.child("nvPr", uri=presentation_uri).unwrap().node,
      "<a:\{kind}File xmlns:a=\"\{drawing_uri}\" xmlns:r=\"\{relationship_uri}\" r:link=\"\{link}Media\"/><p:extLst xmlns:p=\"\{presentation_uri}\"><p:ext uri=\"\{media_extension_uri}\"><p14:media xmlns:p14=\"\{creation_uri}\" xmlns:r=\"\{relationship_uri}\" r:embed=\"\{link}Embedded\"/></p:ext></p:extLst>",
    ),
  ]).0.source()
}
