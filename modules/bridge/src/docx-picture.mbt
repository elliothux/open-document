///|
fn Foundation::docx_flow(
  self : Foundation,
  session : @docx.Session,
) -> Json raise @failure.Failure {
  let flow = session.flow()
  let keys : Array[String] = []
  fn retain(paragraph : @layout.Paragraph) {
    for span in paragraph.spans {
      if span.image is Some(image) && !keys.contains(image.key) {
        keys.push(image.key)
      }
    }
  }
  for paragraph in flow.paragraphs {
    retain(paragraph)
  }
  for
    header in flow.headers.values().to_array() +
    flow.footers.values().to_array() {
    for paragraph in header {
      retain(paragraph)
    }
  }
  for table in flow.tables {
    for row in table.rows {
      for cell in row {
        for paragraph in cell {
          retain(paragraph)
        }
      }
    }
  }
  self.images.retain(keys)
  flow.to_json()
}

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
  if operation == "docxPictureResize" {
    guard request is { "change": change, .. } else {
      @failure.reject("invalid-operation", "Picture resize command is required")
    }
    let result = match field_string(change, "action") {
      "begin" =>
        session.begin_picture_resize(revision, field_int(change, "picture"))
      "cancel" =>
        session.cancel_picture_resize(revision, field_int(change, "id"))
      "update" =>
        session.update_picture_resize(
          revision,
          field_int(change, "id"),
          xlsx_number(change, "dx"),
          xlsx_number(change, "dy"),
          field_int(change, "handle"),
        )
      "commit" =>
        session.finish_picture_resize(
          revision,
          field_int(change, "id"),
          xlsx_number(change, "dx"),
          xlsx_number(change, "dy"),
          field_int(change, "handle"),
        )
      _ =>
        @failure.reject("invalid-operation", "Unknown picture resize command")
    }
    self.layout = None
    return result
  }
  guard request is { "picture": picture, .. } else {
    @failure.reject("invalid-operation", "Picture settings are required")
  }
  let result = match field_string(picture, "action") {
    "insert" =>
      session.insert_picture(
        revision,
        xlsx_number(picture, "width"),
        xlsx_number(picture, "height"),
        input_bytes(picture, 4194304),
      )
    "delete" => session.delete_picture(revision, field_int(picture, "id"))
    "replace" =>
      session.replace_picture(
        revision,
        field_int(picture, "id"),
        input_bytes(picture, 4194304),
      )
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
