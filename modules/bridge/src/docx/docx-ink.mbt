///|
fn ink_stroke(request : Json) -> @model.InkStroke raise @failure.Failure {
  guard request is { "stroke": stroke, .. } &&
    stroke is { "points": Array(points), .. } else {
    @failure.reject("invalid-operation", "Ink samples are required")
  }
  guard points.length() > 0 && points.length() <= 4096 else {
    @failure.reject("limit-exceeded", "Ink requires 1 to 4096 points")
  }
  {
    points: points.map(point => {
      guard point is [Number(x, ..), Number(y, ..)] else {
        @failure.reject(
          "invalid-operation", "Ink samples require coordinate pairs",
        )
      }
      (x, y)
    }),
    color: field_string(stroke, "color"),
    width: field_number(stroke, "width"),
    highlighter: field_boolean(stroke, "highlighter"),
  }
}

///|
fn Context::ink_operation(
  self : Context,
  request : Json,
) -> Json raise @failure.Failure {
  guard self.docx is Some(session) else {
    @failure.reject("invalid-operation", "Open a DOCX session first")
  }
  let revision = field_int(request, "revision")
  let layout = self.current_layout(request)
  let page = field_int(request, "page")
  let action = field_string(request, "action")
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
        profile=font_profile(request),
        images=self.images,
      )
    "erase" =>
      session.erase_ink(
        revision,
        layout,
        page,
        field_number(request, "x"),
        field_number(request, "y"),
      )
    _ => @failure.reject("invalid-operation", "Unknown ink action")
  }
  if result is { "revision": Number(current, ..), .. } &&
    current != revision.to_double() {
    self.layout = None
  }
  result
}
