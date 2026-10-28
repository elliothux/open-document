///|
fn Context::pdf_convert_operation(
  self : Context,
  request : Json,
) -> Json raise @failure.Failure {
  guard self.pdf is Some(session) else {
    @failure.reject("session-required", "Open a PDF first")
  }
  guard request is { "budget": value, .. } else {
    @failure.reject(
      "invalid-budget", "Explicit Office output budget is required",
    )
  }
  let budget : @archive.Budget = {
    file_bytes: field_int(value, "fileBytes"),
    entry_bytes: field_int(value, "entryBytes"),
    total_bytes: field_int(value, "totalBytes"),
    retained_bytes: field_int(value, "retainedBytes"),
    entries: field_int(value, "entries"),
    xml_depth: field_int(value, "xmlDepth"),
    output_bytes: field_int(value, "outputBytes"),
  }
  let result = @convert.convert(
    session,
    field_int(request, "revision"),
    pdf_strings(request, "pages"),
    field_string(request, "format"),
    field_boolean(request, "acceptLoss"),
    budget,
    self.probe,
    font_profile(request),
    decoded=self.images,
  )
  let pages : Array[Json] = result.pages.map(page => {
    "source": page.source,
    "target": page.target,
  })
  let bytes : Json = match result.bytes {
    Some(bytes) => Json::string(@base64.encode(bytes))
    None => Json::null()
  }
  {
    "revision": result.revision,
    "format": result.format,
    "status": result.status,
    "reason": result.reason,
    "warnings": result.warnings,
    "pages": pages,
    "bytes": bytes,
  }
}
