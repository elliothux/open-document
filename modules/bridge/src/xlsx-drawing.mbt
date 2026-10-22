///|
fn xlsx_drawing_request(operation : String) -> Bool {
  [
    "picturesXlsx", "captureDrawingXlsx", "drawingFragmentImageXlsx", "pasteDrawingXlsx",
    "selectDrawingXlsx", "drawingGestureXlsx", "pictureResourceXlsx", "imageBytesXlsx",
    "imageXlsx", "insertPictureXlsx", "replacePictureXlsx", "setPictureXlsx", "deletePictureXlsx",
  ].contains(operation)
}

///|
fn xlsx_move_drawing(change : Json) -> @xlsx.SheetEdit raise @failure.Failure {
  guard change is Object(fields) &&
    fields.length() == 3 &&
    fields
    .keys()
    .all(key => ["action", "sourceSheet", "objectId"].contains(key)) else {
    @failure.reject(
      "invalid-operation", "Invalid worksheet drawing move fields",
    )
  }
  @xlsx.MoveDrawing(
    field_string(change, "sourceSheet"),
    field_string(change, "objectId"),
  )
}

///|
fn xlsx_duplicate_drawing(
  change : Json,
) -> @xlsx.SheetEdit raise @failure.Failure {
  guard change is Object(fields) &&
    fields.length() == 2 &&
    fields.keys().all(key => ["action", "objectId"].contains(key)) else {
    @failure.reject(
      "invalid-operation", "Invalid worksheet drawing copy fields",
    )
  }
  @xlsx.DuplicateDrawing(field_string(change, "objectId"))
}

///|
fn xlsx_drawing_order(change : Json) -> @xlsx.SheetEdit raise @failure.Failure {
  guard change is Object(fields) &&
    fields.length() == 3 &&
    fields.keys().all(key => ["action", "objectId", "direction"].contains(key)) else {
    @failure.reject(
      "invalid-operation", "Invalid worksheet picture layer command fields",
    )
  }
  @xlsx.DrawingOrder(
    field_string(change, "objectId"),
    field_string(change, "direction"),
  )
}

///|
fn Foundation::xlsx_drawing_operation(
  self : Foundation,
  operation : String,
  request : Json,
) -> Json raise @failure.Failure {
  guard self.xlsx is Some(session) else {
    @failure.reject("session-required", "Open an XLSX workbook first")
  }
  let revision = field_int(request, "revision")
  match operation {
    "captureDrawingXlsx" =>
      session.capture_drawing(
        revision,
        field_string(request, "sheet"),
        field_string(request, "objectId"),
        self.probe,
        xlsx_profile(request),
      )
    "drawingFragmentImageXlsx" =>
      session.drawing_fragment_image(
        revision,
        field_string(request, "fragment"),
      )
    "pasteDrawingXlsx" =>
      session.paste_drawing(
        revision,
        field_string(request, "sheet"),
        field_string(request, "fragment"),
        self.probe,
        xlsx_profile(request),
        images=self.images,
      )
    "selectDrawingXlsx" => {
      let picture = match request {
        { "objectId": String(id), .. } => Some(id)
        { "objectId": Null, .. } => None
        _ =>
          @failure.reject(
            "invalid-operation", "Picture identity or null is required",
          )
      }
      session.select_drawing(revision, field_int(request, "layout"), picture)
    }
    "drawingGestureXlsx" =>
      session.drawing_gesture(
        revision,
        field_int(request, "layout"),
        field_int(request, "handle"),
        xlsx_number(request, "dx"),
        xlsx_number(request, "dy"),
        xlsx_boolean(request, "commit"),
        self.probe,
        xlsx_profile(request),
        images=self.images,
      )
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
    "replacePictureXlsx" =>
      session.replace_picture(
        revision,
        field_string(request, "sheet"),
        field_string(request, "id"),
        input_bytes(request, 2097152),
        self.probe,
        xlsx_profile(request),
        images=self.images,
      )
    "setPictureXlsx" => {
      guard request is { "settings": settings, .. } else {
        @failure.reject("invalid-operation", "Picture settings are required")
      }
      guard settings is { "crop": Array(values), .. } && values.length() == 4 else {
        @failure.reject(
          "invalid-operation", "Four picture crop values are required",
        )
      }
      let crop = values.map(value => {
        guard value is Number(number, ..) else {
          @failure.reject("invalid-operation", "Picture crop must be numeric")
        }
        number
      })
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
        crop~,
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
