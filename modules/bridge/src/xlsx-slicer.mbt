///|
fn Foundation::insert_xlsx_slicer(
  self : Foundation,
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
      width: xlsx_number(settings, "width"),
      height: xlsx_number(settings, "height"),
    },
    self.probe,
    xlsx_profile(request),
  )
}
