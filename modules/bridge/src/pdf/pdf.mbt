///|
fn pdf_budget(value : Json) -> @model.PdfBudget raise @failure.Failure {
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
fn Context::pdf_operation(
  self : Context,
  operation : String,
  request : Json,
) -> Json raise @failure.Failure {
  if operation == "defaultPdfBudget" {
    return @model.PdfBudget::default().to_json()
  }
  if operation == "defaultPdfOfficeBudget" {
    return @common.archive_budget()
  }
  if operation == "openPdf" || operation == "createPdf" {
    guard request is { "budget": value, .. } else {
      @failure.reject("invalid-budget", "Explicit PDF budget is required")
    }
    let budget = pdf_budget(value)
    let candidate = if operation == "createPdf" {
      @model.PdfSession::create(
        field_number(request, "width"),
        field_number(request, "height"),
        budget,
      )
    } else {
      @model.PdfSession::open(input_bytes(request, budget.fileBytes), budget)
    }
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
    "convertPdfOffice" => self.pdf_convert_operation(request)
    "previewPdfRedaction" | "exportPdfRedaction" =>
      self.pdf_redaction_operation(operation, request)
    "pdfAnnotation"
    | "pdfAnnotationThread"
    | "editPdfAnnotation"
    | "replyPdfAnnotation"
    | "deletePdfAnnotationThread"
    | "addPdfInkAnnotation"
    | "addPdfStampAnnotation" =>
      self.pdf_annotation_operation(operation, request)
    "pdfFieldDesign" | "updatePdfFieldDesign" =>
      self.pdf_field_design_operation(operation, request)
    "splitPdfPage" | "splitPdfPageGrid" | "nupPdfPages" =>
      self.pdf_arrange_operation(operation, request)
    "splitPdfFiles" => {
      guard request is { "groups": Array(groups), .. } &&
        groups.length() <= 1024 else {
        @failure.reject("invalid-operation", "PDF split groups are required")
      }
      let revision = field_int(request, "revision")
      let groups = groups.map(group => pdf_strings({ "pages": group }, "pages"))
      {
        "revision": revision,
        "files": session
        .split_files(revision, groups)
        .map(file => { "name": file.0, "bytes": @base64.encode(file.1) }),
      }
    }
    "exportPdfText" => {
      let revision = field_int(request, "revision")
      let (bytes, warnings) = session.export_text(
        revision,
        pdf_strings(request, "pages"),
        field_string(request, "format"),
        self.probe,
        font_profile(request),
        decoded=self.images,
      )
      {
        "revision": revision,
        "bytes": @base64.encode(bytes),
        "warnings": warnings,
      }
    }
    "pdfNavigation" => session.navigation()
    "selectPdfRange" =>
      session.select_range(
        field_int(request, "revision"),
        field_string(request, "anchorPage"),
        field_int(request, "anchor"),
        field_string(request, "focusPage"),
        field_int(request, "focus"),
        self.probe,
        font_profile(request),
      )
    "selectedPdfRange" =>
      session.selected_range(
        field_int(request, "revision"),
        self.probe,
        font_profile(request),
      )
    "cropPdfPage" =>
      session.crop_page(
        field_int(request, "revision"),
        field_string(request, "page"),
        field_number(request, "x"),
        field_number(request, "y"),
        field_number(request, "width"),
        field_number(request, "height"),
      )
    "resizePdfPage" =>
      session.resize_page(
        field_int(request, "revision"),
        field_string(request, "page"),
        field_number(request, "width"),
        field_number(request, "height"),
        field_boolean(request, "scaleContent"),
        field_string(request, "anchor"),
      )
    "insertPdfPages" =>
      session.insert_pages(
        field_int(request, "revision"),
        input_bytes(request, 67108864),
        pdf_strings(request, "pages"),
        field_int(request, "index"),
      )
    "replacePdfPages" =>
      session.insert_pages(
        field_int(request, "revision"),
        input_bytes(request, 67108864),
        pdf_strings(request, "pages"),
        field_int(request, "index"),
        replace=pdf_strings(request, "replace"),
      )
    "insertBlankPdfPage" =>
      session.insert_blank(
        field_int(request, "revision"),
        field_int(request, "index"),
        field_number(request, "width"),
        field_number(request, "height"),
      )
    "extractPdfPages" =>
      {
        "revision": field_int(request, "revision"),
        "bytes": @base64.encode(
          session.extract_pages(
            field_int(request, "revision"),
            pdf_strings(request, "pages"),
          ),
        ),
      }
    "pdfMetadata" => session.metadata()
    "setPdfMetadata" => {
      guard request is { "fields": Object(values), .. } else {
        @failure.reject("invalid-operation", "PDF metadata fields are required")
      }
      let fields : Map[String, String] = Map([])
      for key, value in values {
        guard value is String(text) else {
          @failure.reject("invalid-operation", "PDF metadata must be text")
        }
        fields[key] = text
      }
      session.set_metadata(field_int(request, "revision"), fields)
    }
    "renderPdfPage" =>
      session.render(
        field_int(request, "revision"),
        field_string(request, "page"),
        self.probe,
        font_profile(request),
        self.images,
        activate=match request {
          { "activate": True, .. } => true
          { "activate": False, .. } => false
          { "activate": _, .. } =>
            @failure.reject(
              "invalid-operation", "PDF activation must be boolean",
            )
          _ => true
        },
        reuse=match request {
          { "reuse": True, .. } => true
          { "reuse": False, .. } => false
          { "reuse": _, .. } =>
            @failure.reject(
              "invalid-operation", "PDF view reuse must be boolean",
            )
          _ => false
        },
      )
    "releasePdfView" => {
      session.release_view(field_int(request, "layoutId"))
      session.query()
    }
    "extractPdfText" =>
      session.extract(
        field_int(request, "revision"),
        field_string(request, "page"),
        self.probe,
        font_profile(request),
      )
    "searchPdfPage" =>
      session.search(
        field_int(request, "revision"),
        field_string(request, "page"),
        field_string(request, "query"),
        self.probe,
        font_profile(request),
      )
    "hitTestPdf" =>
      session.hit(
        field_int(request, "layoutId"),
        field_number(request, "x"),
        field_number(request, "y"),
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
      let degrees = field_number(request, "degrees")
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
        field_number(request, "x"),
        field_number(request, "y"),
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
        font_profile(request),
      )
    }
    "imagePdf" => {
      let size = if request is { "size": value, .. } {
        Some((field_int(value, "width"), field_int(value, "height")))
      } else {
        None
      }
      let (kind, bytes, width, height) = session.image(
        field_int(request, "layoutId"),
        field_string(request, "key"),
        self.images,
        size~,
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
    "cropPdfImage" => self.pdf_image_crop_operation(request)
    _ => self.pdf_object_operation(operation, request)
  }
}
