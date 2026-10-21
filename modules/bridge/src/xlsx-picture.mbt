///|
fn Foundation::xlsx_picture_operation(
  self : Foundation,
  operation : String,
  request : Json,
) -> Json raise @failure.Failure {
  guard self.xlsx is Some(session) else {
    @failure.reject("session-required", "Open an XLSX workbook first")
  }
  let revision = field_int(request, "revision")
  match operation {
    "picturesXlsx" =>
      session.pictures(
        revision,
        field_string(request, "sheet"),
        self.probe,
        xlsx_profile(request),
      )
    "pictureResourceXlsx" =>
      session.picture_resource(revision, input_bytes(request, 2097152))
    "imageBytesXlsx" =>
      {
        "bytes": @base64.encode(
          session.picture_image(revision, field_string(request, "key")),
        ),
      }
    "imageXlsx" => {
      let keys = session.picture_keys(revision)
      let key = field_string(request, "key")
      keys.push(key)
      self.images.retain(keys)
      self.images.add(
        key,
        field_int(request, "width"),
        field_int(request, "height"),
        input_bytes(request, 16777216),
      )
      { "key": self.images.get(key).identity }
    }
    "insertPictureXlsx" =>
      session.insert_picture(
        revision,
        field_string(request, "sheet"),
        xlsx_number(request, "width"),
        xlsx_number(request, "height"),
        input_bytes(request, 2097152),
        self.probe,
        xlsx_profile(request),
        name=field_string(request, "name"),
        description=field_string(request, "description"),
        images=self.images,
      )
    "setPictureXlsx" => {
      guard request is { "settings": settings, .. } else {
        @failure.reject("invalid-operation", "Picture settings are required")
      }
      session.set_picture(
        revision,
        field_string(request, "sheet"),
        field_string(request, "id"),
        field_string(settings, "anchor"),
        {
          x: xlsx_number(settings, "x"),
          y: xlsx_number(settings, "y"),
          width: xlsx_number(settings, "width"),
          height: xlsx_number(settings, "height"),
        },
        field_string(settings, "name"),
        field_string(settings, "description"),
        self.probe,
        xlsx_profile(request),
      )
    }
    "deletePictureXlsx" =>
      session.delete_picture(
        revision,
        field_string(request, "sheet"),
        field_string(request, "id"),
        self.probe,
        xlsx_profile(request),
      )
    _ =>
      @failure.reject(
        "invalid-operation", "Unknown worksheet picture operation",
      )
  }
}
