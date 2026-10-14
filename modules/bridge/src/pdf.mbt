///|
fn pdf_budget(value : Json) -> @pdf.PdfBudget raise @failure.Failure {
  {
    fileBytes: field_int(value, "fileBytes"),
    objects: field_int(value, "objects"),
    objectNumber: field_int(value, "objectNumber"),
    pages: field_int(value, "pages"),
    revisions: field_int(value, "revisions"),
    depth: field_int(value, "depth"),
    streamBytes: field_int(value, "streamBytes"),
    decodedBytes: field_int(value, "decodedBytes"),
    steps: field_int(value, "steps"),
    outputBytes: field_int(value, "outputBytes"),
  }
}

///|
fn pdf_strings(
  request : Json,
  key : String,
) -> Array[String] raise @failure.Failure {
  guard request is Object(fields) &&
    fields.get(key) is Some(Array(values)) &&
    values.length() <= 1024 else {
    @failure.reject(
      "invalid-operation", "Bounded PDF page identities are required",
    )
  }
  values.map(value => {
    guard value is String(text) else {
      @failure.reject("invalid-operation", "PDF page identity must be a string")
    }
    text
  })
}

///|
fn Foundation::pdf_operation(
  self : Foundation,
  operation : String,
  request : Json,
) -> Json raise @failure.Failure {
  if operation == "defaultPdfBudget" {
    return @pdf.PdfBudget::default().to_json()
  }
  if operation == "openPdf" {
    guard self.docx is None && self.xlsx is None && self.pptx is None else {
      @failure.reject(
        "invalid-operation", "A different document format is already open",
      )
    }
    guard request is { "budget": value, .. } else {
      @failure.reject("invalid-budget", "Explicit PDF budget is required")
    }
    let budget = pdf_budget(value)
    let candidate = @pdf.PdfSession::open(
      input_bytes(request, budget.fileBytes),
      budget,
    )
    errdefer candidate.close()
    let result = candidate.query()
    if self.pdf is Some(previous) {
      previous.close()
    }
    self.images.clear()
    self.pdf = Some(candidate)
    return result
  }
  guard self.pdf is Some(session) else {
    @failure.reject("session-required", "Open a PDF first")
  }
  match operation {
    "queryPdf" => session.query()
    "renderPdfPage" =>
      session.render(
        field_int(request, "revision"),
        field_string(request, "page"),
        self.probe,
        xlsx_profile(request),
        self.images,
      )
    "extractPdfText" =>
      session.extract(
        field_int(request, "revision"),
        field_string(request, "page"),
        self.probe,
        xlsx_profile(request),
      )
    "searchPdfPage" =>
      session.search(
        field_int(request, "revision"),
        field_string(request, "page"),
        field_string(request, "query"),
        self.probe,
        xlsx_profile(request),
      )
    "hitTestPdf" =>
      session.hit(
        field_int(request, "layoutId"),
        xlsx_number(request, "x"),
        xlsx_number(request, "y"),
      )
    "selectPdf" =>
      session.select_text(
        field_int(request, "layoutId"),
        field_int(request, "anchor"),
        field_int(request, "focus"),
      )
    "selectedPdfText" =>
      { "text": session.selected_text(field_int(request, "layoutId")) }
    "savePdf" =>
      {
        "revision": field_int(request, "revision"),
        "bytes": @base64.encode(session.save(field_int(request, "revision"))),
      }
    "undoPdf" | "redoPdf" =>
      session.undo_edit(field_int(request, "revision"), operation == "redoPdf")
    "reorderPdfPages" =>
      session.reorder(
        field_int(request, "revision"),
        pdf_strings(request, "pages"),
      )
    "deletePdfPages" =>
      session.delete_pages(
        field_int(request, "revision"),
        pdf_strings(request, "pages"),
      )
    "rotatePdfPages" => {
      let degrees = xlsx_number(request, "degrees")
      guard degrees >= -36000 &&
        degrees <= 36000 &&
        degrees == degrees.to_int().to_double() else {
        @failure.reject(
          "invalid-operation", "PDF rotation requires bounded integer degrees",
        )
      }
      session.rotate_pages(
        field_int(request, "revision"),
        pdf_strings(request, "pages"),
        degrees.to_int(),
      )
    }
    "addPdfNote" =>
      session.add_note(
        field_int(request, "revision"),
        field_string(request, "page"),
        xlsx_number(request, "x"),
        xlsx_number(request, "y"),
        field_string(request, "text"),
      )
    "highlightPdfText" =>
      session.add_highlight(
        field_int(request, "revision"),
        field_int(request, "layoutId"),
      )
    "updatePdfAnnotation" | "deletePdfAnnotation" =>
      session.change_annotation(
        field_int(request, "revision"),
        field_string(request, "page"),
        field_string(request, "annotation"),
        if operation == "deletePdfAnnotation" {
          ""
        } else {
          field_string(request, "text")
        },
        operation == "deletePdfAnnotation",
      )
    "setPdfFieldValue" => {
      guard request is { "value": value, .. } else {
        @failure.reject("invalid-operation", "PDF field value is required")
      }
      session.set_field(
        field_int(request, "revision"),
        field_string(request, "field"),
        value,
        self.probe,
        xlsx_profile(request),
      )
    }
    "imagePdf" => {
      let (kind, bytes, width, height) = session.image(
        field_int(request, "layoutId"),
        field_string(request, "key"),
        self.images,
      )
      {
        "kind": kind,
        "bytes": @base64.encode(bytes),
        "width": width,
        "height": height,
      }
    }
    "decodedImagePdf" => {
      let key = field_string(request, "key")
      session.decoded_image(
        field_int(request, "layoutId"),
        key,
        field_int(request, "width"),
        field_int(request, "height"),
        input_bytes(request, 16777216),
        self.images,
      )
      let image = self.images.get(key)
      {
        "kind": "rgba",
        "bytes": @base64.encode(image.rgba),
        "width": image.width,
        "height": image.height,
      }
    }
    _ => @failure.reject("invalid-operation", "Unknown PDF operation")
  }
}
