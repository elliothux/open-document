///|
fn Foundation::shape_operation(
  self : Foundation,
  operation : String,
  request : Json,
) -> Json raise @failure.Failure {
  guard self.docx is Some(session) else {
    @failure.reject("invalid-operation", "Open a DOCX session first")
  }
  let revision = field_int(request, "revision")
  if operation == "docxShapes" {
    return session.shapes(revision)
  }
  guard request is { "shape": shape, .. } else {
    @failure.reject("invalid-operation", "Shape settings are required")
  }
  let result = match field_string(shape, "action") {
    "insert" =>
      session.insert_shape(
        revision,
        field_string(shape, "preset"),
        xlsx_number(shape, "width"),
        xlsx_number(shape, "height"),
        field_string(shape, "fill"),
        field_string(shape, "stroke"),
        xlsx_number(shape, "lineWidth"),
        probe=self.probe,
        profile=xlsx_profile(request),
        images=self.images,
      )
    "delete" => session.delete_shape(revision, field_int(shape, "id"))
    "position" =>
      session.set_drawing_anchor(
        revision,
        field_int(shape, "id"),
        drawing_anchor(shape),
        target?=if shape is { "target": target, .. } {
          Some(field_position(target))
        } else {
          None
        },
        probe=self.probe,
        profile=xlsx_profile(request),
        images=self.images,
      )
    "properties" =>
      session.edit_shape(
        revision,
        field_int(shape, "id"),
        xlsx_number(shape, "width"),
        xlsx_number(shape, "height"),
        field_string(shape, "fill"),
        field_string(shape, "stroke"),
        xlsx_number(shape, "lineWidth"),
        probe=self.probe,
        profile=xlsx_profile(request),
        images=self.images,
      )
    _ => @failure.reject("invalid-operation", "Unknown shape action")
  }
  if result is { "revision": Number(current, ..), .. } &&
    current != revision.to_double() {
    self.layout = None
  }
  result
}
