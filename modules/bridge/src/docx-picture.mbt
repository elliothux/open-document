///|
fn Foundation::picture_operation(
  self : Foundation,
  operation : String,
  request : Json,
) -> Json raise @failure.Failure {
  guard self.docx is Some(session) else {
    @failure.reject("invalid-operation", "Open a DOCX session first")
  }
  let revision = field_int(request, "revision")
  if operation == "docxPictures" {
    return session.pictures(revision)
  }
  guard request is { "picture": picture, .. } else {
    @failure.reject("invalid-operation", "Picture settings are required")
  }
  let result = match field_string(picture, "action") {
    "delete" => session.delete_picture(revision, field_int(picture, "id"))
    "resize" => resize_picture(session, revision, picture)
    _ => @failure.reject("invalid-operation", "Invalid picture action")
  }
  if result is { "revision": Number(current, ..), .. } &&
    current != revision.to_double() {
    self.layout = None
  }
  result
}

///|
fn resize_picture(
  session : @docx.Session,
  revision : Int,
  picture : Json,
) -> Json raise @failure.Failure {
  guard picture
    is {
      "crop": Array(values),
      "width": Number(width, ..),
      "height": Number(height, ..),
      ..
    } else {
    @failure.reject("invalid-operation", "Picture settings are required")
  }
  let crop = values.map(value => {
    match value {
      Number(value, ..) => value
      _ => @failure.reject("invalid-operation", "Invalid crop value")
    }
  })
  session.edit_picture(revision, field_int(picture, "id"), width, height, crop)
}
