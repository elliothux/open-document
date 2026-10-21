///|
fn Foundation::clipboard_command(
  self : Foundation,
  session : @docx.Session,
  request : Json,
) -> Json raise @failure.Failure {
  let revision = field_int(request, "revision")
  match field_string(request, "operation") {
    "selectedText" =>
      Json(
        session.selected_text(
          revision,
          field_selection(request),
          cut=xlsx_boolean(request, "cut"),
          layout?=self.layout,
        ),
      )
    "tableClipboard" =>
      session.table_clipboard(
        revision,
        field_selection(request),
        cut=xlsx_boolean(request, "cut"),
        layout?=self.layout,
      )
    "docxClipboard" =>
      session.clipboard(
        revision,
        field_selection(request),
        cut=xlsx_boolean(request, "cut"),
        layout?=self.layout,
      )
    "tableFragmentImages" =>
      session.table_fragment_images(revision, field_string(request, "fragment"))
    "bodyFragmentImages" =>
      session.body_fragment_images(revision, field_string(request, "fragment"))
    "pasteBodyFragment" => {
      let result = session.paste_body_fragment(
        revision,
        field_selection(request),
        field_string(request, "fragment"),
        self.probe,
        xlsx_profile(request),
        images=Some(self.images),
      )
      self.layout = None
      result
    }
    _ =>
      @failure.reject(
        "invalid-operation", "Unknown document clipboard operation",
      )
  }
}
