///|
fn Foundation::docx_theme_fonts(
  self : Foundation,
  session : @docx.Session,
  request : Json,
) -> Json raise @failure.Failure {
  guard request is { "fonts": Object(fields) as fonts, .. } &&
    fields.length() == 2 &&
    fields.contains("major") &&
    fields.contains("minor") else {
    @failure.reject("invalid-operation", "Invalid DOCX theme font pair")
  }
  let revision = field_int(request, "revision")
  let result = session.set_theme_fonts(
    revision,
    field_string(fonts, "major"),
    field_string(fonts, "minor"),
    self.probe,
    xlsx_profile(request),
  )
  if result is { "revision": Number(current, ..), .. } &&
    current != revision.to_double() {
    self.layout = None
  }
  result
}
