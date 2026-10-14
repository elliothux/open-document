///|
fn Foundation::pptx_operation(
  self : Foundation,
  operation : String,
  request : Json,
) -> Json raise @failure.Failure {
  if operation == "openPptx" {
    guard self.docx is None &&
      self.xlsx is None &&
      self.pptx is None &&
      self.pdf is None else {
      @failure.reject("invalid-operation", "A document session is already open")
    }
    guard request is { "budget": budget, .. } else {
      @failure.reject("invalid-budget", "Explicit budget is required")
    }
    let budget : @archive.Budget = {
      file_bytes: field_int(budget, "fileBytes"),
      entry_bytes: field_int(budget, "entryBytes"),
      total_bytes: field_int(budget, "totalBytes"),
      retained_bytes: field_int(budget, "retainedBytes"),
      entries: field_int(budget, "entries"),
      xml_depth: field_int(budget, "xmlDepth"),
      output_bytes: field_int(budget, "outputBytes"),
    }
    let session = @pptx.Session::open(
      input_bytes(request, budget.file_bytes.min(budget.retained_bytes)),
      budget,
    )
    let result = session.query()
    self.pptx = Some(session)
    return result
  }
  guard self.pptx is Some(session) else {
    @failure.reject("session-required", "Open a PPTX presentation first")
  }
  match operation {
    "queryPptx" => session.query()
    "selectPptx" =>
      session.select(
        field_int(request, "revision"),
        field_string(request, "slide"),
        field_string(request, "object"),
        field_string(request, "mode"),
        field_int(request, "anchor"),
        field_int(request, "focus"),
      )
    "replacePptx" =>
      session.replace(
        field_int(request, "revision"),
        field_string(request, "text"),
        self.probe,
        xlsx_profile(request),
        candidate_id=if request is Object(fields) &&
          fields.contains("candidateId") {
          Some(field_int(request, "candidateId"))
        } else {
          None
        },
      )
    "deletePptx" =>
      session.delete(
        field_int(request, "revision"),
        xlsx_boolean(request, "backward"),
        self.probe,
        xlsx_profile(request),
      )
    "undoPptx" | "redoPptx" =>
      session.undo(field_int(request, "revision"), redo=operation == "redoPptx")
    "savePptx" =>
      { "bytes": @base64.encode(session.save(field_int(request, "revision"))) }
    "layoutPptx" =>
      session.layout(self.probe, xlsx_profile(request), self.images)
    "hitPptx" =>
      session.hit(
        field_int(request, "layoutId"),
        xlsx_number(request, "x"),
        xlsx_number(request, "y"),
        xlsx_number(request, "tolerance"),
      )
    "selectionPptx" =>
      session.selection_geometry(field_int(request, "layoutId"))
    "navigatePptx" =>
      session.navigate(
        field_int(request, "revision"),
        field_int(request, "layoutId"),
        field_string(request, "direction"),
        xlsx_boolean(request, "extend"),
      )
    "beginPptx" =>
      session.begin(
        field_int(request, "revision"),
        field_string(request, "kind"),
      )
    "transformPptx" =>
      session.transform(
        field_int(request, "revision"),
        field_int(request, "candidateId"),
        xlsx_number(request, "x"),
        xlsx_number(request, "y"),
        xlsx_number(request, "width"),
        xlsx_number(request, "height"),
      )
    "dragPptx" =>
      session.drag(
        field_int(request, "revision"),
        field_int(request, "candidateId"),
        xlsx_number(request, "dx"),
        xlsx_number(request, "dy"),
        field_int(request, "handle"),
      )
    "finishPptx" =>
      session.finish(
        field_int(request, "revision"),
        field_int(request, "candidateId"),
        self.probe,
        xlsx_profile(request),
      )
    "cancelPptx" =>
      session.cancel(
        field_int(request, "revision"),
        field_int(request, "candidateId"),
      )
    "copyPptx" => { "text": session.copy(field_int(request, "revision")) }
    "imageBytesPptx" =>
      {
        "bytes": @base64.encode(
          session.image_bytes(field_string(request, "key")),
        ),
      }
    "imagePptx" => {
      let key = field_string(request, "key")
      ignore(session.image_bytes(key))
      self.images.add(
        key,
        field_int(request, "width"),
        field_int(request, "height"),
        input_bytes(request, 16777216),
      )
      session.invalidate_geometry()
      { "key": self.images.get(key).identity }
    }
    "imageKeysPptx" => {
      let keys = session.image_keys(
        xlsx_boolean(request, "all"),
        xlsx_boolean(request, "hidden"),
      )
      self.images.retain(keys)
      Json(keys)
    }
    "exportPptxPdf" => {
      let document = session.print_layout(
        field_int(request, "revision"),
        xlsx_boolean(request, "all"),
        xlsx_boolean(request, "hidden"),
        self.probe,
        xlsx_profile(request),
      )
      {
        "bytes": @base64.encode(
          @pdf.write(
            document,
            self.probe,
            self.images,
            field_int(request, "outputBytes"),
          ),
        ),
      }
    }
    _ => @failure.reject("invalid-operation", "Unknown PPTX operation")
  }
}
