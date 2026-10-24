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
    "hyperlink" => drawing_hyperlink(session, revision, shape)
    "insertWordArt" =>
      session.insert_word_art(
        revision,
        field_string(shape, "preset"),
        field_string(shape, "text"),
        probe=self.probe,
        profile=xlsx_profile(request),
        images=self.images,
      )
    "insert" =>
      session.insert_shape(
        revision,
        field_string(shape, "preset"),
        xlsx_number(shape, "width"),
        xlsx_number(shape, "height"),
        field_string(shape, "fill"),
        field_string(shape, "stroke"),
        xlsx_number(shape, "lineWidth"),
        text?=if shape is Object(fields) && fields.contains("text") {
          Some(field_string(shape, "text"))
        } else {
          None
        },
        probe=self.probe,
        profile=xlsx_profile(request),
        images=self.images,
      )
    "delete" => session.delete_shape(revision, field_int(shape, "id"))
    "textBox" => {
      guard shape is { "properties": properties, .. } &&
        properties is { "insets": Array(insets), .. } else {
        @failure.reject("invalid-operation", "Text box properties are required")
      }
      session.edit_text_box(
        revision,
        field_int(shape, "id"),
        {
          insets: insets.map(value => {
            guard value is Number(number, ..) else {
              @failure.reject(
                "invalid-operation", "Text box insets require numbers",
              )
            }
            number
          }),
          anchor: field_string(properties, "anchor"),
          wrap: xlsx_boolean(properties, "wrap"),
          clip: xlsx_boolean(properties, "clip"),
        },
        probe=self.probe,
        profile=xlsx_profile(request),
        images=self.images,
      )
    }
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
