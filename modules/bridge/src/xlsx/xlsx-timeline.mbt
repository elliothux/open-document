///|
fn Context::insert_xlsx_timeline(
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
    @failure.reject(
      "invalid-operation", "Native timeline settings are required",
    )
  }
  session.insert_timeline(
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
