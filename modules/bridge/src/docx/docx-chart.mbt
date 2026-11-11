///|
priv struct ChartEditRequest {
  revision : @common.RequestInt
  chart : Json?
  profile : Json?
} derive(@json.FromJson)

///|
priv struct ChartGeometryRequest {
  width : @common.RequestNumber
  height : @common.RequestNumber
} derive(@json.FromJson)

///|
priv struct ChartContentRequest {
  kind : String
  title : String
  data : String
  holeSize : @common.RequestInt?
  legend : String?
} derive(@json.FromJson)

///|
fn Context::edit_chart_command(
  self : Context,
  session : @model.Session,
  request : Json,
) -> Json raise @failure.Failure {
  let input : ChartEditRequest = @common.request(request)
  let revision = input.revision.value
  guard input.chart is Some(Object(fields) as chart) else {
    @failure.reject("invalid-operation", "Chart settings are required")
  }
  let command : @common.ActionRequest = @common.request(chart)
  let action = command.action
  guard ["insert", "update", "delete", "resize", "position"].contains(action) else {
    @failure.reject("invalid-operation", "Unknown chart action")
  }
  let keys = ["action"]
  if action != "insert" {
    keys.push("id")
  }
  let content = action == "insert" || action == "update"
  if content {
    keys.append(["kind", "title", "data", "width", "height"])
    for key in ["holeSize", "legend"] {
      match fields.get(key) {
        Some(Null) =>
          @failure.reject("invalid-operation", "Invalid chart option: " + key)
        Some(_) => keys.push(key)
        None => ()
      }
    }
  }
  if action == "resize" {
    keys.append(["width", "height"])
  }
  if action == "position" {
    keys.push("anchor")
    if fields.contains("target") {
      keys.push("target")
    }
  }
  guard fields.length() == keys.length() &&
    fields.keys().all(key => keys.contains(key)) else {
    @failure.reject("invalid-operation", "Unknown chart settings")
  }
  let result = if action == "position" {
    self.position_drawing(session, revision, chart, input.profile)
  } else {
    let id = if action == "insert" {
      -1
    } else {
      let drawing : DrawingIdRequest = @common.request(chart)
      drawing.id.value
    }
    let (width, height) = if action == "delete" {
      (0.0, 0.0)
    } else {
      let geometry : ChartGeometryRequest = @common.request(chart)
      (geometry.width.value, geometry.height.value)
    }
    let data : ChartContentRequest = if content {
      @common.request(chart)
    } else {
      { kind: "", title: "", data: "", holeSize: None, legend: None, }
    }
    session.edit_chart(
      revision,
      action,
      id,
      data.kind,
      data.title,
      data.data,
      width,
      height,
      hole_size=data.holeSize.map(size => size.value),
      legend=data.legend,
      probe=self.probe,
      profile=drawing_profile(input.profile),
      images=self.images,
    )
  }
  self.clear_edit_layout(result, previous=revision)
}
