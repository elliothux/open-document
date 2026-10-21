///|
fn Session::frame_placeholder_reason(
  self : Session,
  object : Object,
  kinds : Array[String],
) -> String {
  let reason = self.empty_placeholder_reason(object, kinds)
  if !reason.is_empty() {
    return reason
  }
  if object.source.tree.document.nodes()[0].name != "sld" {
    return "Fill frame placeholders in the slide view"
  }
  let geometry = object.geometry.unwrap()
  if geometry.rotation != 0 || geometry.flip_x || geometry.flip_y {
    return "Native frames do not support rotation or flipping"
  }
  let source = object.source
  let pending = source.tree.children
    .get(source.node.id)
    .unwrap_or([])
    .filter(node => node.name != "nvSpPr")
  while pending.pop() is Some(node) {
    if ![presentation_uri, drawing_uri].contains(node.uri) ||
      node.name == "extLst" ||
      node.attributes.any(attribute => !attribute.uri.is_empty()) {
      return "Extended placeholder content is protected"
    }
    pending.append(source.tree.children.get(node.id).unwrap_or([]))
  }
  ""
}

///|
fn Session::table_fill_reason(self : Session, object : Object) -> String {
  self.frame_placeholder_reason(object, ["tbl", "obj"])
}

///|
fn Session::fill_table(
  self : Session,
  rows : Int,
  columns : Int,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  guard self.selection.mode == "object" && self.selection.objects.length() == 1 else {
    @failure.reject("invalid-operation", "Select one table placeholder")
  }
  guard rows >= 1 &&
    rows <= 1000 &&
    columns >= 1 &&
    columns <= 63 &&
    rows.to_int64() * columns.to_int64() <= 4096 else {
    @failure.reject("invalid-operation", "Invalid table dimensions")
  }
  let original = self.current()
  let object = original.object(self.selection.object)
  let reason = self.table_fill_reason(object)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let geometry = object.geometry.unwrap()
  let source = object.source
  let nv = source.child("nvSpPr", uri=presentation_uri).unwrap()
  let id = object.id[original.tree.part.length() + 1:].to_owned()
  // ONLYOFFICE takes the placeholder position and width; row content determines height.
  let markup = table_markup(
    id,
    rows,
    columns,
    geometry.x,
    geometry.y,
    geometry.width,
    0.1,
  )
  let document = @xml.Document::parse(
    @utf8.encode(markup),
    original.tree.part,
    self.budget.xml_depth,
    self.budget.entry_bytes,
  )
  let tree = Tree::new(original.tree.part, document)
  let frame : Ref = { tree, node: tree.document.nodes()[0], }
  let target = frame.child("nvGraphicFramePr", uri=presentation_uri).unwrap()
  let (document, _) = document.edit_source(
    ["cNvPr", "nvPr"].map(name => {
      table_source_change(
        target.child(name, uri=presentation_uri).unwrap(),
        source.tree.standalone_markup(
          source.tree.document,
          nv.child(name, uri=presentation_uri).unwrap().node.id,
        ),
      )
    }),
  )
  let (candidate, edit) = self.prepare_table(
    original,
    [table_source_change(source, document.source())],
    object.id,
    probe,
    profile,
  )
  self.commit(candidate, edit, self.selection, probe~, profile~)
  self.query()
}
