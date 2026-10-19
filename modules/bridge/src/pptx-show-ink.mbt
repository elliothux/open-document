///|
fn pptx_show_ink(
  session : @pptx.Session,
  request : Json,
) -> Json raise @failure.Failure {
  guard request is { "change": value, .. } else {
    @failure.reject("invalid-operation", "Missing ink change")
  }
  let action = field_string(value, "action")
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
    guard value is { "points": Array(points), .. } && points.length() <= 64 else {
      @failure.reject("invalid-operation", "Invalid ink point batch")
    }
    points.map(point => {
      guard point is Object(fields) &&
        fields.length() == 2 &&
        fields.contains("x") &&
        fields.contains("y") else {
        @failure.reject("invalid-operation", "Invalid ink point")
      }
      (xlsx_number(point, "x"), xlsx_number(point, "y"))
    })
  } else {
    []
  }
  session.ink_show(
    field_int(request, "revision"),
    field_int(request, "layoutId"),
    xlsx_number(request, "time"),
    match action {
      "begin" =>
        @pptx.BeginInk(
          field_string(value, "color"),
          xlsx_number(value, "width"),
          points,
        )
      "append" => @pptx.AppendInk(points)
      "end" => @pptx.FinishInk(points)
      "cancel" => @pptx.CancelInk
      _ => @pptx.ClearInk
    },
  )
}
