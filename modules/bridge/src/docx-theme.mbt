///|
fn Foundation::docx_theme_fonts(
  self : Foundation,
  session : @docx.Session,
  request : Json,
) -> Json raise @failure.Failure {
  guard request is { "fonts": Array(fonts), .. } &&
    !fonts.is_empty() &&
    fonts.length() <= 6 else {
    @failure.reject("invalid-operation", "Invalid DOCX theme font changes")
  }
  let changes = fonts.map(font => {
    guard font is Object(fields) &&
      fields.length() == 3 &&
      fields.keys().all(key => ["kind", "script", "font"].contains(key)) else {
      @failure.reject("invalid-operation", "Invalid DOCX theme font change")
    }
    @docx.ThemeFontEdit::{
      kind: field_string(font, "kind"),
      script: field_string(font, "script"),
      font: field_string(font, "font"),
    }
  })
  let revision = field_int(request, "revision")
  let result = session.set_theme_fonts(
    revision,
    changes,
    self.probe,
    xlsx_profile(request),
  )
  if result is { "revision": Number(current, ..), .. } &&
    current != revision.to_double() {
    self.layout = None
  }
  result
}
