///|
#derive(ToJson)
priv struct ChartQuery {
  id : String
  anchor : String
  x : Double
  y : Double
  width : Double
  height : Double
  name : String
  description : String
  kind : String
  title : String
  label : String
  legend : String
  holeSize : QueryNullable[Int32]
  categories : String
  names : Array[String]
  values : Array[String]
  data : String
  bindingReason : String
}

///|
pub fn Session::charts(
  self : Session,
  revision : Int32,
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
  let result : DrawingQuery[ChartQuery] = {
    revision,
    sheet,
    reason,
    items: objects
    .iter()
    .filter(object => object.chart is Some(_))
    .map(object => {
      let chart = object.chart.unwrap().1
      let settings = sheet_chart_settings(chart)
      ChartQuery::{
        id: object.id,
        anchor: object.anchor,
        x: object.rect.x,
        y: object.rect.y,
        width: object.rect.width,
        height: object.rect.height,
        name: object.name,
        description: object.description,
        kind: if chart.native_bubble is Some(_) {
          "bubble"
        } else {
          settings.kind
        },
        title: settings.title,
        label: settings.label,
        legend: settings.legend,
        holeSize: { value: settings.hole_size, },
        categories: settings.categories,
        names: settings.names,
        values: settings.values,
        data: chart.data.tsv(),
        bindingReason: if object.chart_pending {
          uncalculated_chart_reason
        } else {
          chart_binding_reason(chart)
        },
      }
    })
    .to_array(),
  }
  ToJson::to_json(result)
}

///|
pub fn Session::delete_chart(
  self : Session,
  revision : Int32,
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
