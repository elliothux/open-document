///|
fn Foundation::pptx_import(
  self : Foundation,
  session : @pptx.Session,
  request : Json,
  commit : Bool,
) -> Json raise @failure.Failure {
  guard request is { "indices": Array(values), .. } && values.length() <= 256 else {
    @failure.reject(
      "invalid-slide", "Explicit bounded source slide indices are required",
    )
  }
  let indices = values.map(value => {
    match value {
      Number(value, ..) if value.floor() == value && value >= 0 && value < 256 =>
        value.to_int()
      _ => @failure.reject("invalid-slide", "Invalid source slide index")
    }
  })
  let bytes = input_bytes(request, 33554432)
  if commit {
    session.import_slides(
      field_int(request, "revision"),
      bytes,
      indices,
      field_string(request, "after"),
      self.probe,
      xlsx_profile(request),
    )
  } else {
    session.import_slide_info(field_int(request, "revision"), bytes, indices)
  }
}
