///|
fn xlsx_shape_color(
  settings : Json,
  name : String,
) -> String? raise @failure.Failure {
  guard settings is Object(fields) else {
    @failure.reject("invalid-operation", "Shape settings are required")
  }
  match fields.get(name) {
    Some(String(value)) => Some(value)
    Some(Null) => None
    _ => @failure.reject("invalid-operation", "Shape color or null is required")
  }
}

///|
fn Context::xlsx_shape_operation(
  self : Context,
  operation : String,
  request : Json,
) -> Json raise @failure.Failure {
  guard self.xlsx is Some(session) else {
    @failure.reject("session-required", "Open an XLSX workbook first")
  }
  let revision = field_int(request, "revision")
  let sheet = field_string(request, "sheet")
  let profile = font_profile(request)
  match operation {
    "shapesXlsx" => session.shapes(revision, sheet, self.probe, profile)
    "insertShapeXlsx" =>
      session.insert_shape(
        revision,
        sheet,
        field_string(request, "kind"),
        field_number(request, "width"),
        field_number(request, "height"),
        field_string(request, "text"),
        self.probe,
        profile,
      )
    "deleteShapeXlsx" =>
      session.delete_shape(
        revision,
        sheet,
        field_string(request, "id"),
        self.probe,
        profile,
      )
    "setShapeXlsx" => {
      guard request is { "settings": settings, .. } &&
        settings is { "insets": insets, .. } else {
        @failure.reject(
          "invalid-operation", "Shape settings and insets are required",
        )
      }
      session.set_shape(
        revision,
        sheet,
        field_string(request, "id"),
        {
          kind: field_string(settings, "kind"),
          anchor: field_string(settings, "anchor"),
          rect: {
            x: field_number(settings, "x"),
            y: field_number(settings, "y"),
            width: field_number(settings, "width"),
            height: field_number(settings, "height"),
          },
          name: field_string(settings, "name"),
          description: field_string(settings, "description"),
          fill: xlsx_shape_color(settings, "fill"),
          stroke: xlsx_shape_color(settings, "stroke"),
          line_width: field_number(settings, "lineWidth"),
          text: field_string(settings, "text"),
          font: field_string(settings, "font"),
          bold: field_boolean(settings, "bold"),
          italic: field_boolean(settings, "italic"),
          size: field_number(settings, "size"),
          color: field_string(settings, "color"),
          wrap: field_boolean(settings, "wrap"),
          align: field_string(settings, "align"),
          vertical: field_string(settings, "vertical"),
          insets: ["left", "top", "right", "bottom"].map(name => {
            field_number(insets, name)
          }),
        },
        self.probe,
        profile,
      )
    }
    _ =>
      @failure.reject("invalid-operation", "Unknown worksheet shape operation")
  }
}
