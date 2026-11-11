///|
priv struct ChartEditRequest {
  kind : String
  title : String
  data : String
  holeSize : @common.RequestInt?
  legend : String?
} derive(@json.FromJson)

///|
fn pptx_chart_edit(
  action : String,
  change : Json,
) -> @model.ObjectEdit raise @failure.Failure {
  let insert = action == "insertChart"
  let keys = if insert {
    ["action", "kind", "title", "data", "x", "y", "width", "height"]
  } else {
    ["action", "kind", "title", "data"]
  }
  guard change is Object(fields) else {
    @failure.reject("invalid-operation", "Invalid chart edit fields")
  }
  for key in ["holeSize", "legend"] {
    if fields.get(key) is Some(value) {
      guard !(value is Null) else {
        @failure.reject("invalid-operation", "Chart option cannot be null")
      }
      keys.push(key)
    }
  }
  guard fields.length() == keys.length() &&
    fields.keys().all(key => keys.contains(key)) else {
    @failure.reject("invalid-operation", "Invalid chart edit fields")
  }
  let request : ChartEditRequest = @common.request(change)
  let hole_size = request.holeSize.map(value => value.value)
  if insert {
    let frame : ObjectFrameRequest = @common.request(change)
    @model.InsertChart(
      request.kind,
      request.title,
      request.data,
      frame.x.value,
      frame.y.value,
      frame.width.value,
      frame.height.value,
      hole_size,
      request.legend,
    )
  } else if action == "fillChart" {
    @model.FillChart(
      request.kind,
      request.title,
      request.data,
      hole_size,
      request.legend,
    )
  } else {
    @model.ChartData(
      request.kind,
      request.title,
      request.data,
      hole_size,
      request.legend,
    )
  }
}
