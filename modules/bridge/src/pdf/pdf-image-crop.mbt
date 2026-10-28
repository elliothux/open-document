///|
fn Context::pdf_image_crop_operation(
  self : Context,
  request : Json,
) -> Json raise @failure.Failure {
  guard self.pdf is Some(session) else {
    @failure.reject("session-required", "Open a PDF first")
  }
  guard request is { "crop": crop, .. } else {
    @failure.reject("invalid-operation", "Image crop window is required")
  }
  session.crop_image(
    field_int(request, "revision"),
    field_string(request, "page"),
    field_string(request, "object"),
    {
      x: field_number(crop, "x"),
      y: field_number(crop, "y"),
      width: field_number(crop, "width"),
      height: field_number(crop, "height"),
    },
    self.probe,
    font_profile(request),
  )
}
