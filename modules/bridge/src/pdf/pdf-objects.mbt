///|
fn pdf_placement(value : Json) -> @model.PdfPlacement raise @failure.Failure {
  {
    x: field_number(value, "x"),
    y: field_number(value, "y"),
    width: field_number(value, "width"),
    height: field_number(value, "height"),
    rotation: field_number(value, "rotation"),
  }
}

///|
fn pdf_text_spec(value : Json) -> @model.PdfTextSpec raise @failure.Failure {
  guard value is { "placement": placement, .. } else {
    @failure.reject("invalid-operation", "PDF text placement is required")
  }
  {
    placement: pdf_placement(placement),
    text: field_string(value, "text"),
    font: field_string(value, "font"),
    size: field_number(value, "size"),
    color: field_string(value, "color"),
    role: field_string(value, "role"),
    foreground: field_boolean(value, "foreground"),
  }
}

///|
fn Context::pdf_object_operation(
  self : Context,
  operation : String,
  request : Json,
) -> Json raise @failure.Failure {
  guard self.pdf is Some(session) else {
    @failure.reject("session-required", "Open a PDF first")
  }
  let revision = field_int(request, "revision")
  match operation {
    "pdfObjects" =>
      session.objects(
        revision,
        field_string(request, "page"),
        self.probe,
        font_profile(request),
      )
    "addPdfText" | "replacePdfText" => {
      guard request is { "spec": spec, .. } else {
        @failure.reject(
          "invalid-operation", "PDF text specification is required",
        )
      }
      if operation == "addPdfText" {
        session.add_text(
          revision,
          pdf_strings(request, "pages"),
          pdf_text_spec(spec),
          self.probe,
          font_profile(request),
        )
      } else {
        session.replace_text(
          revision,
          field_string(request, "page"),
          field_string(request, "object"),
          pdf_text_spec(spec),
          self.probe,
          font_profile(request),
        )
      }
    }
    "addPdfImage" => {
      guard request is { "placement": placement, .. } else {
        @failure.reject("invalid-operation", "PDF image placement is required")
      }
      session.add_image(
        revision,
        field_string(request, "page"),
        pdf_placement(placement),
        field_int(request, "pixelWidth"),
        field_int(request, "pixelHeight"),
        input_bytes(request, 16777216),
        self.probe,
        font_profile(request),
        replace=match request {
          { "replace": String(id), .. } => id
          { "replace": _, .. } =>
            @failure.reject(
              "invalid-operation", "PDF image replacement identity must be text",
            )
          _ => ""
        },
      )
    }
    "movePdfObject" => {
      guard request is { "placement": placement, .. } else {
        @failure.reject("invalid-operation", "PDF object placement is required")
      }
      session.move_object(
        revision,
        field_string(request, "page"),
        field_string(request, "object"),
        pdf_placement(placement),
        self.probe,
        font_profile(request),
      )
    }
    "deletePdfObject" =>
      session.delete_object(
        revision,
        field_string(request, "page"),
        field_string(request, "object"),
        self.probe,
        font_profile(request),
      )
    _ => @failure.reject("invalid-operation", "Unknown PDF object operation")
  }
}
