///|
pub fn Session::set_chart_frame(
  self : Session,
  revision : Int,
  sheet : String,
  id : String,
  anchor : String,
  rect : @layout.Border,
  name : String,
  description : String,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let current = self.sheets[self.sheet_index(sheet)]
  let reason = self.dimension_reason(current)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let dimensions = self.resolved_dimensions(current, probe, profile)
  check_picture_rect(anchor, rect, dimensions)
  check_picture_text(name, description)
  let object = self
    .sheet_objects(current, dimensions)
    .iter()
    .find_first(object => object.id == id && object.chart is Some(_))
    .unwrap_or_else(() => {
      @failure.reject("invalid-operation", "Worksheet chart no longer exists")
    })
  object.check_change(false, rect~)
  if (
      object.anchor,
      object.rect.x,
      object.rect.y,
      object.rect.width,
      object.rect.height,
      object.name,
      object.description,
    ) ==
    (anchor, rect.x, rect.y, rect.width, rect.height, name, description) {
    return self.query()
  }
  ignore(
    object.chart.unwrap().1.data.paint(rect.width, rect.height, probe, profile),
  )
  let nv = object.tree.picture_node(object.source.id, "nvGraphicFramePr")
  let identity = object.tree.picture_node(nv.id, "cNvPr")
  let changes = metadata_changes(identity, [
    ("name", name),
    ("descr", description),
  ])
  changes.push(object.transform_change(rect))
  let (document, metadata) = object.tree.document.edit_source(changes)
  let tree = Tree::new(document)
  let source = tree.picture_markup(object.source.id)
  let frame = tree.nodes[object.frame.id]
  let client_data = tree
    .picture_child(frame.id, "clientData")
    .map(node => tree.picture_markup(node.id))
    .unwrap_or("<odXdr:clientData/>")
  let (document, edit) = document.edit_source([
    {
      node: frame.parent,
      offset: frame.start - tree.nodes[frame.parent].start,
      length: frame.end - frame.start,
      xml: picture_frame_source(anchor, rect, source, dimensions, client_data~),
    },
  ])
  let parts = self.parts.copy()
  parts[object.part] = document
  let candidate = { ..self, parts, }
  ignore(candidate.sheet_objects(current, dimensions))
  self.commit(
    self.sheets,
    self.workbook,
    self.calculation.unwrap(),
    [(object.part, metadata), (object.part, edit)],
    self.selection,
    parts~,
    drawing_selection=self.drawing_selection,
    font_context=Some((probe, profile.copy())),
  )
  self.query()
}
