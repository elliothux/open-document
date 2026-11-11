///|
#derive(@json.FromJson)
priv struct ShowInkPointRequest {
  x : @common.RequestNumber
  y : @common.RequestNumber
}

///|
#derive(@json.FromJson)
priv struct ShowInkStyleRequest {
  color : String
  width : @common.RequestNumber
}

///|
fn pptx_show_ink(value : Json) -> @model.ShowInkChange raise @failure.Failure {
  let command : @common.ActionRequest = @common.request(value)
  let action = command.action
  let keys = match action {
    "begin" => ["action", "color", "width", "points"]
    "append" | "end" => ["action", "points"]
    "cancel" | "clear" => ["action"]
    _ => @failure.reject("invalid-operation", "Unknown ink action")
  }
  guard value is Object(fields) &&
    fields.length() == keys.length() &&
    fields.keys().all(key => keys.contains(key)) else {
    @failure.reject("invalid-operation", "Invalid ink fields")
  }
  let points = if keys.contains("points") {
    guard value is { "points": Array(points), .. } &&
      points.length() <= @model.ShowInkBatchPoints else {
      @failure.reject("invalid-operation", "Invalid ink point batch")
    }
    points.map(point => {
      guard point is Object(fields) && fields.length() == 2 else {
        @failure.reject("invalid-operation", "Invalid ink point")
      }
      let point : ShowInkPointRequest = @common.request(point)
      (point.x.value, point.y.value)
    })
  } else {
    []
  }
  match action {
    "begin" => {
      let style : ShowInkStyleRequest = @common.request(value)
      @model.BeginInk(style.color, style.width.value, points)
    }
    "append" => @model.AppendInk(points)
    "end" => @model.FinishInk(points)
    "cancel" => @model.CancelInk
    _ => @model.ClearInk
  }
}
