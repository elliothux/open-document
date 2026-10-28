///|
fn pdf_field_widget_design(
  value : Json,
) -> @model.PdfFieldWidgetDesign raise @failure.Failure {
  guard value is { "placement": placement, .. } else {
    @failure.reject("invalid-operation", "Widget placement is required")
  }
  {
    id: field_string(value, "id"),
    page: field_string(value, "page"),
    placement: pdf_placement(placement),
    border: field_number(value, "border"),
    borderColor: field_string(value, "borderColor"),
    background: field_string(value, "background"),
    exportValue: field_string(value, "exportValue"),
  }
}

///|
fn Context::pdf_field_design_operation(
  self : Context,
  operation : String,
  request : Json,
) -> Json raise @failure.Failure {
  guard self.pdf is Some(session) else {
    @failure.reject("session-required", "Open a PDF first")
  }
  let revision = field_int(request, "revision")
  let field = field_string(request, "field")
  match operation {
    "pdfFieldDesign" => session.field_design(revision, field)
    "updatePdfFieldDesign" => {
      guard request is { "spec": spec, "widgets": Array(widgets), .. } &&
        widgets.length() <= 4096 else {
        @failure.reject(
          "invalid-operation", "Field design and bounded widgets are required",
        )
      }
      session.update_field_design(
        revision,
        field,
        pdf_field_design(spec),
        widgets.map(pdf_field_widget_design),
        self.probe,
        font_profile(request),
      )
    }
    _ =>
      @failure.reject("invalid-operation", "Unknown PDF field design operation")
  }
}
