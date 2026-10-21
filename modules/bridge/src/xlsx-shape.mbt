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
fn Foundation::xlsx_shape_operation(
  self : Foundation,
  operation : String,
  request : Json,
) -> Json raise @failure.Failure {
  guard self.xlsx is Some(session) else {
    @failure.reject("session-required", "Open an XLSX workbook first")
  }
  let revision = field_int(request, "revision")
  let sheet = field_string(request, "sheet")
  let profile = xlsx_profile(request)
  match operation {
    "shapesXlsx" => session.shapes(revision, sheet, self.probe, profile)
    "insertShapeXlsx" =>
      session.insert_shape(
        revision,
        sheet,
        field_string(request, "kind"),
        xlsx_number(request, "width"),
        xlsx_number(request, "height"),
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
            x: xlsx_number(settings, "x"),
            y: xlsx_number(settings, "y"),
            width: xlsx_number(settings, "width"),
            height: xlsx_number(settings, "height"),
          },
          name: field_string(settings, "name"),
          description: field_string(settings, "description"),
          fill: xlsx_shape_color(settings, "fill"),
          stroke: xlsx_shape_color(settings, "stroke"),
          line_width: xlsx_number(settings, "lineWidth"),
          text: field_string(settings, "text"),
          font: field_string(settings, "font"),
          bold: xlsx_boolean(settings, "bold"),
          italic: xlsx_boolean(settings, "italic"),
          size: xlsx_number(settings, "size"),
          color: field_string(settings, "color"),
          wrap: xlsx_boolean(settings, "wrap"),
          align: field_string(settings, "align"),
          vertical: field_string(settings, "vertical"),
          insets: ["left", "top", "right", "bottom"].map(name => {
            xlsx_number(insets, name)
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
