///|
fn Session::chart_fill_reason(self : Session, object : Object) -> String {
  let reason = self.frame_placeholder_reason(object, ["chart", "obj"])
  if !reason.is_empty() {
    return reason
  }
  let geometry = object.geometry.unwrap()
  if geometry.width < 180 || geometry.height < 150 {
    return "Chart frame requires at least 180 x 150 points"
  }
  ""
}

///|
fn placeholder_chart_change(
  object : Object,
  link : String,
  budget : @archive.Budget,
) -> @xml.SourceChange raise @failure.Failure {
  let g = object.geometry.unwrap()
  let source = object.source
  let nv = source.child("nvSpPr", uri=presentation_uri).unwrap()
  let document = @xml.Document::parse(
    @utf8.encode(chart_frame("1", link, g.x, g.y, g.width, g.height)),
    source.tree.part,
    budget.xml_depth,
    budget.entry_bytes,
  )
  let tree = Tree::new(source.tree.part, document)
  let frame : Ref = { tree, node: document.nodes()[0], }
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
  // Retain the placeholder identity and application metadata in the native frame.
  table_source_change(source, document.source())
}
