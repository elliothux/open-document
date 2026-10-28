///|
fn Context::pptx_clipboard(
  self : Context,
  session : @model.Session,
  operation : String,
  request : Json,
) -> Json raise @failure.Failure {
  let revision = field_int(request, "revision")
  if operation == "copyPptx" {
    session.copy(revision)
  } else if operation == "objectFragmentImagesPptx" {
    Json(
      session.object_fragment_images(
        revision,
        field_string(request, "fragment"),
      ),
    )
  } else if operation == "objectFragmentMediaPptx" {
    Json(
      session.object_fragment_media(revision, field_string(request, "fragment")),
    )
  } else if operation == "pastePptxObjects" {
    session.paste_object_fragment(
      revision,
      field_string(request, "fragment"),
      self.probe,
      font_profile(request),
    )
  } else {
    session.paste_text_fragment(
      revision,
      field_string(request, "fragment"),
      self.probe,
      font_profile(request),
    )
  }
}
