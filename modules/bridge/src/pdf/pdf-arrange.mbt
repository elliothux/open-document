///|
fn Context::pdf_arrange_operation(
  self : Context,
  operation : String,
  request : Json,
) -> Json raise @failure.Failure {
  guard self.pdf is Some(session) else {
    @failure.reject("session-required", "Open a PDF first")
  }
  let revision = field_int(request, "revision")
  let page = match request {
    { "page": String(page), .. } => page
    _ => ""
  }
  match operation {
    "splitPdfPage" => {
      guard request is { "regions": Array(regions), .. } &&
        regions.length() <= 1024 else {
        @failure.reject(
          "invalid-operation", "Bounded split regions are required",
        )
      }
      session.split_page(revision, page, regions.map(pdf_placement))
    }
    "splitPdfPageGrid" =>
      session.split_page_grid(
        revision,
        page,
        field_int(request, "columns"),
        field_int(request, "rows"),
      )
    "nupPdfPages" =>
      session.nup_pages(
        revision,
        pdf_strings(request, "pages"),
        field_int(request, "columns"),
        field_int(request, "rows"),
        field_number(request, "width"),
        field_number(request, "height"),
      )
    _ => @failure.reject("invalid-operation", "Unknown PDF page arrangement")
  }
}
