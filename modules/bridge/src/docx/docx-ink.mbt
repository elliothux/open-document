///|
priv struct InkStrokeStyle {
  color : String
  width : @common.RequestNumber
  highlighter : Bool
} derive(@json.FromJson)

///|
fn ink_stroke(request : Json) -> @model.InkStroke raise @failure.Failure {
  guard request is { "stroke": stroke, .. } &&
    stroke is { "points": Array(points), .. } else {
    @failure.reject("invalid-operation", "Ink samples are required")
  }
  guard points.length() > 0 && points.length() <= @model.InkStrokePoints else {
    @failure.reject(
      "limit-exceeded",
      "Ink requires 1 to \{@model.InkStrokePoints} points",
    )
  }
  let samples = points.map(point => {
    guard point is [Number(x, ..), Number(y, ..)] else {
      @failure.reject(
        "invalid-operation", "Ink samples require coordinate pairs",
      )
    }
    (x, y)
  })
  let style : InkStrokeStyle = @common.request(stroke)
  {
    points: samples,
    color: style.color,
    width: style.width.value,
    highlighter: style.highlighter,
  }
}

///|
priv struct InkOperationRequest {
  action : String
  page : @common.RequestInt
  profile : Json?
} derive(@json.FromJson)

///|
priv struct InkEraseRequest {
  x : @common.RequestNumber
  y : @common.RequestNumber
} derive(@json.FromJson)

///|
fn Context::ink_operation(
  self : Context,
  session : @model.Session,
  request : Json,
) -> Json raise @failure.Failure {
  let revision = @common.request_revision(request)
  let layout = self.current_layout(request)
  let command : InkOperationRequest = @common.request(request)
  let page = command.page.value
  let action = command.action
  if action == "preview" {
    return session.preview_ink(revision, layout, page, ink_stroke(request))
  }
  let result = match action {
    "insert" =>
      session.insert_ink(
        revision,
        layout,
        page,
        ink_stroke(request),
        probe=self.probe,
        profile=drawing_profile(command.profile),
        images=self.images,
      )
    "erase" => {
      let point : InkEraseRequest = @common.request(request)
      session.erase_ink(revision, layout, page, point.x.value, point.y.value)
    }
    _ => @failure.reject("invalid-operation", "Unknown ink action")
  }
  self.clear_edit_layout(result, previous=revision)
}
