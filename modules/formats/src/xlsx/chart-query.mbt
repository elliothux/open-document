///|
pub fn Session::charts(
  self : Session,
  revision : Int,
  sheet : String,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let current = self.sheets[self.sheet_index(sheet)]
  let mut reason = self.dimension_reason(current)
  let objects = self.sheet_objects(
    current,
    self.resolved_dimensions(current, probe, profile),
  ) catch {
    @failure.Failure(code="limit-exceeded", ..) as error => raise error
    @failure.Failure(message~, ..) => {
      reason = message
      []
    }
  }
  {
    "revision": revision,
    "sheet": sheet,
    "reason": reason,
    "items": objects
    .iter()
    .filter(object => object.chart is Some(_))
    .map(object => {
      let chart = object.chart.unwrap().1
      let settings = sheet_chart_settings(chart)
      let value : Json = {
        "id": object.id,
        "anchor": object.anchor,
        "x": object.rect.x,
        "y": object.rect.y,
        "width": object.rect.width,
        "height": object.rect.height,
        "name": object.name,
        "description": object.description,
        "kind": settings.kind,
        "title": settings.title,
        "label": settings.label,
        "legend": settings.legend,
        "holeSize": settings.hole_size
        .map(value => Json(value))
        .unwrap_or(Json::null()),
        "categories": settings.categories,
        "names": settings.names,
        "values": settings.values,
        "data": chart.data.tsv(),
        "bindingReason": chart_binding_reason(chart),
      }
      value
    })
    .to_array(),
  }
}

///|
pub fn Session::delete_chart(
  self : Session,
  revision : Int,
  sheet : String,
  id : String,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let current = self.sheets[self.sheet_index(sheet)]
  let reason = self.dimension_reason(current)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let object = self
    .sheet_objects(current, self.resolved_dimensions(current, probe, profile))
    .iter()
    .find_first(object => object.id == id && object.chart is Some(_))
    .unwrap_or_else(() => {
      @failure.reject("invalid-operation", "Worksheet chart no longer exists")
    })
  object.check_change(true)
  let (document, edit) = object.tree.document.edit_source([
    sheet_node_removal(object.tree, object.frame),
  ])
  let parts = self.parts.copy()
  parts[object.part] = document
  self.commit(
    self.sheets,
    self.workbook,
    self.calculation.unwrap(),
    [(object.part, edit)],
    self.selection,
    parts~,
  )
  self.query()
}
