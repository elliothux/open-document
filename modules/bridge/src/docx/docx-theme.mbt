///|
priv struct ThemeFontRequest {
  kind : String
  script : String
  font : String
} derive(@json.FromJson)

///|
priv struct ThemeFontsRequest {
  revision : @common.RequestInt
  profile : @common.RequestProfile
} derive(@json.FromJson)

///|
fn Context::docx_theme_fonts(
  self : Context,
  session : @model.Session,
  request : Json,
) -> Json raise @failure.Failure {
  guard request is { "fonts": Array(fonts), .. } &&
    !fonts.is_empty() &&
    fonts.length() <= 6 else {
    @failure.reject("invalid-operation", "Invalid DOCX theme font changes")
  }
  let changes = fonts.map(font => {
    guard font is Object(fields) && fields.length() == 3 else {
      @failure.reject("invalid-operation", "Invalid DOCX theme font change")
    }
    let font : ThemeFontRequest = @common.request(font)
    @model.ThemeFontEdit::{
      kind: font.kind,
      script: font.script,
      font: font.font,
    }
  })
  let command : ThemeFontsRequest = @common.request(request)
  let revision = command.revision.value
  let result = session.set_theme_fonts(
    revision,
    changes,
    self.probe,
    command.profile.value,
  )
  self.clear_edit_layout(result, previous=revision)
}
