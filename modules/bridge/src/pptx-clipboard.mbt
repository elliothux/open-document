///|
fn Foundation::pptx_clipboard(
  self : Foundation,
  session : @pptx.Session,
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
  } else if operation == "pastePptxObjects" {
    session.paste_object_fragment(
      revision,
      field_string(request, "fragment"),
      self.probe,
      xlsx_profile(request),
    )
  } else {
    session.paste_text_fragment(
      revision,
      field_string(request, "fragment"),
      self.probe,
      xlsx_profile(request),
    )
  }
}
