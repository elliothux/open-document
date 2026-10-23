///|
/// Sets the native slicer drawing frame without changing its control or cache.
pub fn Session::set_slicer_frame(
  self : Session,
  revision : Int,
  sheet : String,
  id : String,
  anchor : String,
  rect : @layout.Border,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let current = self.sheets[self.sheet_index(sheet)]
  let reason = self.dimension_reason(current)
  guard reason.is_empty() && current.state == "visible" else {
    @failure.reject(
      "protected-content", "Slicer worksheet is protected or hidden",
    )
  }
  let dimensions = self.resolved_dimensions(current, probe, profile)
  check_picture_rect(anchor, rect, dimensions)
  let object = self
    .sheet_objects(current, dimensions)
    .iter()
    .find_first(object => object.id == id && object.slicer is Some(_))
    .unwrap_or_else(() => {
      @failure.reject(
        "invalid-operation", "Worksheet slicer drawing no longer exists",
      )
    })
  object.check_change(false, rect~, slicer_frame=true)
  if (
      object.anchor,
      object.rect.x,
      object.rect.y,
      object.rect.width,
      object.rect.height,
    ) ==
    (anchor, rect.x, rect.y, rect.width, rect.height) {
    return self.query()
  }
  let content = object.tree
    .picture_child(
      object.frame.id,
      "AlternateContent",
      uri=drawing_compatibility_uri,
    )
    .unwrap_or(object.source)
  let source = object.tree.document.source()
  let outside = source[object.frame.start:content.start].to_owned() +
    source[content.end:object.frame.end].to_owned()
  guard !outside.contains("<!--") && !outside.contains("<?") else {
    @failure.reject(
      "protected-content", "Slicer anchor annotations require preservation support",
    )
  }
  let (document, transform) = object.tree.document.edit_source([
    object.transform_change(rect),
  ])
  let tree = Tree::new(document)
  let frame = tree.nodes[object.frame.id]
  let content = tree
    .picture_child(frame.id, "AlternateContent", uri=drawing_compatibility_uri)
    .unwrap_or_else(() => tree.compatible_graphic(frame).unwrap())
  let client_data = tree
    .picture_child(frame.id, "clientData")
    .map(node => tree.picture_markup(node.id))
    .unwrap_or("<odXdr:clientData/>")
  let (document, edit) = document.edit_source([
    {
      node: frame.parent,
      offset: frame.start - tree.nodes[frame.parent].start,
      length: frame.end - frame.start,
      xml: picture_frame_source(
        anchor,
        rect,
        tree.picture_markup(content.id),
        dimensions,
        client_data~,
      ),
    },
  ])
  let parts = self.parts.copy()
  parts[object.part] = document
  let candidate = { ..self, parts, }
  let next = candidate
    .sheet_objects(current, dimensions)
    .iter()
    .find_first(object => object.id == id)
    .unwrap()
  let painted : Array[@layout.PositionedPrimitive] = []
  next.paint(painted, next.rect, probe, profile)
  self.commit(
    self.sheets,
    self.workbook,
    self.calculation.unwrap(),
    [(object.part, transform), (object.part, edit)],
    self.selection,
    parts~,
    drawing_selection=self.drawing_selection,
    font_context=Some((probe, profile.copy())),
  )
  self.query()
}
