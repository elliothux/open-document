///|
fn pdf_redaction_regions(
  request : Json,
) -> Array[@model.PdfRedactionRegion] raise @failure.Failure {
  guard request is { "regions": Array(regions), .. } &&
    !regions.is_empty() &&
    regions.length() <= 4096 else {
    @failure.reject(
      "invalid-selection", "Choose bounded PDF redaction rectangles",
    )
  }
  regions.map(region => {
    page: field_string(region, "page"),
    x: field_number(region, "x"),
    y: field_number(region, "y"),
    width: field_number(region, "width"),
    height: field_number(region, "height"),
  })
}

///|
fn Context::pdf_redaction_operation(
  self : Context,
  operation : String,
  request : Json,
) -> Json raise @failure.Failure {
  guard self.pdf is Some(session) else {
    @failure.reject("session-required", "Open a PDF first")
  }
  let revision = field_int(request, "revision")
  let regions = pdf_redaction_regions(request)
  let profile = font_profile(request)
  match operation {
    "previewPdfRedaction" =>
      session.preview_redaction(
        revision,
        regions,
        self.probe,
        profile,
        decoded=self.images,
      )
    "exportPdfRedaction" => {
      let (bytes, warnings) = session.export_redaction(
        revision,
        regions,
        self.probe,
        profile,
        decoded=self.images,
      )
      {
        "revision": revision,
        "bytes": @base64.encode(bytes),
        "warnings": warnings,
      }
    }
    _ => @failure.reject("invalid-operation", "Unknown PDF redaction operation")
  }
}
