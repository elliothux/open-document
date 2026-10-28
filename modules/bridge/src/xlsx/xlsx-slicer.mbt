///|
fn xlsx_slicer_hover(request : Json) -> (String, Int32)? raise @failure.Failure {
  guard request is { "slicerHover": value, .. } else { return None }
  guard value is Object(fields) &&
    fields.length() == 2 &&
    fields.contains("object") &&
    fields.contains("index") else {
    @failure.reject("invalid-viewport", "Invalid slicer hover fields")
  }
  Some((field_string(value, "object"), field_int(value, "index")))
}

///|
fn Context::insert_xlsx_slicer(
  self : Context,
  request : Json,
) -> Json raise @failure.Failure {
  guard self.xlsx is Some(session) &&
    request is { "settings": Object(fields) as settings, .. } &&
    fields.length() == 6 &&
    fields
    .keys()
    .all(key => {
      ["pivot", "field", "name", "caption", "width", "height"].contains(key)
    }) else {
    @failure.reject("invalid-operation", "Native slicer settings are required")
  }
  session.insert_slicer(
    field_int(request, "revision"),
    field_string(request, "sheet"),
    {
      pivot: field_string(settings, "pivot"),
      field: field_int(settings, "field"),
      name: field_string(settings, "name"),
      caption: field_string(settings, "caption"),
      width: field_number(settings, "width"),
      height: field_number(settings, "height"),
    },
    self.probe,
    font_profile(request),
  )
}

///|
fn Context::set_xlsx_analysis_frame(
  self : Context,
  request : Json,
  timeline~ : Bool = false,
) -> Json raise @failure.Failure {
  guard self.xlsx is Some(session) &&
    request is { "frame": Object(fields) as frame, .. } &&
    fields.length() == 5 &&
    fields
    .keys()
    .all(key => ["anchor", "x", "y", "width", "height"].contains(key)) else {
    @failure.reject("invalid-operation", "Native analysis frame is required")
  }
  if timeline {
    return session.set_timeline_frame(
      field_int(request, "revision"),
      field_string(request, "sheet"),
      field_string(request, "objectId"),
      field_string(frame, "anchor"),
      {
        x: field_number(frame, "x"),
        y: field_number(frame, "y"),
        width: field_number(frame, "width"),
        height: field_number(frame, "height"),
      },
      self.probe,
      font_profile(request),
    )
  }
  session.set_slicer_frame(
    field_int(request, "revision"),
    field_string(request, "sheet"),
    field_string(request, "objectId"),
    field_string(frame, "anchor"),
    {
      x: field_number(frame, "x"),
      y: field_number(frame, "y"),
      width: field_number(frame, "width"),
      height: field_number(frame, "height"),
    },
    self.probe,
    font_profile(request),
  )
}
