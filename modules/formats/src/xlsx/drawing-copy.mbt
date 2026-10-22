///|
fn Session::duplicate_drawing(
  self : Session,
  sheet : String,
  id : String,
) -> Json raise @failure.Failure {
  guard id.length() <= 10 else {
    @failure.reject("invalid-operation", "Invalid worksheet drawing identity")
  }
  let number = @string.parse_int(id[:]) catch {
    _ =>
      @failure.reject("invalid-operation", "Invalid worksheet drawing identity")
  }
  guard number > 0 && number.to_string() == id else {
    @failure.reject("invalid-operation", "Invalid worksheet drawing identity")
  }
  let current = self.sheets[self.sheet_index(sheet)]
  let reason = self.dimension_reason(current)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  guard self.font_context is Some((probe, profile)) else {
    @failure.reject("missing-font", "Measure worksheet drawings before copying")
  }
  let dimensions = self.resolved_dimensions(current, probe, profile)
  let objects = self.sheet_objects(current, dimensions)
  guard objects.length() < 256 else {
    @failure.reject("limit-exceeded", "Worksheet drawings exceed 256 entries")
  }
  let object = objects
    .iter()
    .find_first(object => object.id == id)
    .unwrap_or_else(() => {
      @failure.reject("invalid-operation", "Worksheet drawing no longer exists")
    })
  let identity = object.transfer_identity(true)
  let tree = object.tree
  let rel_uri = relationship_uri[:relationship_uri.length() - 1].to_owned()
  let next_id = for index in 1..<=16384 {
    if !objects.any(object => object.id == index.to_string()) {
      break index.to_string()
    }
  } nobreak {
    @failure.reject("limit-exceeded", "Worksheet drawing identities exhausted")
  }
  let rect = { ..object.rect, x: object.rect.x + 12, y: object.rect.y + 12, }
  guard rect.x + rect.width <= dimensions.columns.position(16385) &&
    rect.y + rect.height <= dimensions.rows.position(1048577) else {
    @failure.reject(
      "invalid-operation", "Copied drawing would exceed the worksheet",
    )
  }
  let changes = object.transfer_changes(identity, next_id, rect, dimensions)
  let parts = self.parts.copy()
  let created : Map[String, @xml.Document] = Map([])
  let edits : Array[(String, @xml.Edit)] = []
  if object.chart is Some((part, _)) {
    guard !self.relationships().any(link => link.owner == part) else {
      @failure.reject(
        "protected-content", "Chart resources require independent copying support",
      )
    }
    let (_, relation) = self.create_sheet_resource(
      object.part,
      "chart",
      self.part_xml(part).source(),
      parts,
      created,
      edits,
    )
    let chart_node = tree.document
      .nodes()
      .iter()
      .find_first(node => {
        node.start >= object.source.start &&
        node.end <= object.source.end &&
        node.uri == chart_uri &&
        node.name == "chart"
      })
      .unwrap()
    let attribute = chart_node.attributes
      .iter()
      .find_first(a => a.uri == rel_uri && a.name == "id")
      .unwrap()
    changes.push({
      node: chart_node.id,
      offset: attribute.start - chart_node.start,
      length: attribute.end - attribute.start,
      xml: escaped_attribute(relation),
    })
  }
  let (copy, _) = tree.document.edit_source(changes)
  let markup = Tree::new(copy).picture_markup(object.frame.id)
  let (document, edit) = tree.document.edit_source([
    insertion(tree.nodes[0], markup),
  ])
  parts[object.part] = document
  edits.push((object.part, edit))
  let candidate = { ..self, parts, }
  ignore(candidate.sheet_objects(current, dimensions))
  self.commit(
    self.sheets,
    self.workbook,
    self.calculation.unwrap(),
    edits,
    self.selection,
    parts~,
    created_parts=created,
    drawing_selection=Some((sheet, next_id)),
  )
  self.query()
}
