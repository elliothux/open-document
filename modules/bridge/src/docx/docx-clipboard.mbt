///|
fn Context::clipboard_command(
  self : Context,
  session : @model.Session,
  request : Json,
) -> Json raise @failure.Failure {
  let revision = field_int(request, "revision")
  match field_string(request, "operation") {
    "selectedText" =>
      Json(
        session.selected_text(
          revision,
          field_selection(request),
          cut=field_boolean(request, "cut"),
          layout?=self.layout,
        ),
      )
    "tableClipboard" =>
      session.table_clipboard(
        revision,
        field_selection(request),
        cut=field_boolean(request, "cut"),
        layout?=self.layout,
      )
    "docxClipboard" =>
      session.clipboard(
        revision,
        field_selection(request),
        cut=field_boolean(request, "cut"),
        layout?=self.layout,
      )
    "tableFragmentImages" =>
      session.table_fragment_images(revision, field_string(request, "fragment"))
    "bodyFragmentImages" =>
      session.body_fragment_images(revision, field_string(request, "fragment"))
    "markupImages" =>
      session.markup_images(
        revision,
        field_string(request, "kind"),
        field_string(request, "input"),
        mode=field_string(request, "mode"),
      )
    "pasteHtml" => {
      let result = session.paste_html(
        revision,
        field_selection(request),
        field_string(request, "html"),
        self.probe,
        font_profile(request),
        images=Some(self.images),
        mode=field_string(request, "mode"),
      )
      self.layout = None
      result
    }
    "pasteMarkdown" => {
      let result = session.paste_markdown(
        revision,
        field_selection(request),
        field_string(request, "markdown"),
        self.probe,
        font_profile(request),
        images=Some(self.images),
        mode=field_string(request, "mode"),
      )
      self.layout = None
      result
    }
    "pasteBodyFragment" => {
      let result = session.paste_body_fragment(
        revision,
        field_selection(request),
        field_string(request, "fragment"),
        self.probe,
        font_profile(request),
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
