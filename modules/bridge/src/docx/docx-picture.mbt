///|
fn Context::docx_flow(
  self : Context,
  session : @model.Session,
) -> Json raise @failure.Failure {
  let flow = session.flow()
  let keys : Array[String] = []
  fn retain(paragraph : @layout.Paragraph) {
    for span in paragraph.spans {
      if span.drawing is Some({ content: @layout.Picture(key, _), .. }) &&
        !keys.contains(key) {
        keys.push(key)
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
    for paragraph in table.paragraphs() {
      retain(paragraph)
    }
  }
  if session.watermark(flow.revision, 0) is { "images": Array(images), .. } {
    for image in images {
      if image is String(key) && !keys.contains(key) {
        keys.push(key)
      }
    }
  }
  self.images.retain(keys)
  flow.to_json()
}

///|
fn Context::picture_operation(
  self : Context,
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
  if operation == "docxDrawingGesture" {
    guard request is { "change": change, .. } else {
      @failure.reject(
        "invalid-operation", "Picture gesture command is required",
      )
    }
    let result = match field_string(change, "action") {
      "begin" =>
        session.begin_drawing_gesture(
          revision,
          field_int(change, "drawing"),
          field_int(change, "handle"),
          probe=self.probe,
          profile=font_profile(request),
          images=self.images,
        )
      "cancel" =>
        session.cancel_drawing_gesture(revision, field_int(change, "id"))
      "update" =>
        session.update_drawing_gesture(
          revision,
          field_int(change, "id"),
          field_number(change, "dx"),
          field_number(change, "dy"),
          page?=if change is { "page": _, .. } {
            Some(field_int(change, "page"))
          } else {
            None
          },
        )
      "commit" =>
        session.finish_drawing_gesture(
          revision,
          field_int(change, "id"),
          field_number(change, "dx"),
          field_number(change, "dy"),
          page?=if change is { "page": _, .. } {
            Some(field_int(change, "page"))
          } else {
            None
          },
        )
      _ =>
        @failure.reject("invalid-operation", "Unknown picture gesture command")
    }
    self.layout = None
    return result
  }
  guard request is { "picture": picture, .. } else {
    @failure.reject("invalid-operation", "Picture settings are required")
  }
  let result = match field_string(picture, "action") {
    "hyperlink" => drawing_hyperlink(session, revision, picture)
    "insert" =>
      session.insert_picture(
        revision,
        field_number(picture, "width"),
        field_number(picture, "height"),
        input_bytes(picture, 4194304),
      )
    "delete" => session.delete_picture(revision, field_int(picture, "id"))
    "replace" =>
      session.replace_picture(
        revision,
        field_int(picture, "id"),
        input_bytes(picture, 4194304),
      )
    "resize" =>
      resize_picture(
        session,
        revision,
        picture,
        self.probe,
        font_profile(request),
        self.images,
      )
    "position" =>
      session.set_drawing_anchor(
        revision,
        field_int(picture, "id"),
        drawing_anchor(picture),
        target?=if picture is { "target": target, .. } {
          Some(field_position(target))
        } else {
          None
        },
        probe=self.probe,
        profile=font_profile(request),
        images=self.images,
      )
    _ => @failure.reject("invalid-operation", "Invalid picture action")
  }
  if result is { "revision": Number(current, ..), .. } &&
    current != revision.to_double() {
    self.layout = None
  }
  result
}

///|
fn drawing_hyperlink(
  session : @model.Session,
  revision : Int32,
  change : Json,
) -> Json raise @failure.Failure {
  guard change is { "target": target, .. } else {
    @failure.reject("invalid-operation", "Drawing hyperlink target is required")
  }
  let target = match target {
    Null => None
    String(value) => Some(value)
    _ =>
      @failure.reject("invalid-operation", "Invalid drawing hyperlink target")
  }
  session.set_drawing_hyperlink(revision, field_int(change, "id"), target)
}

///|
fn drawing_anchor(
  picture : Json,
) -> @layout.DrawingAnchor? raise @failure.Failure {
  guard picture is { "anchor": value, .. } else {
    @failure.reject("invalid-operation", "Picture anchor is required")
  }
  if value is Null {
    return None
  }
  fn axis(value : Json) -> @layout.DrawingAxis raise @failure.Failure {
    let reference = field_string(value, "relativeTo")
    match value {
      { "offset": Number(offset, ..), "align": Null, .. } =>
        @layout.Offset(reference, offset)
      { "offset": Null, "align": String(align), .. } =>
        @layout.Aligned(reference, align)
      _ => @failure.reject("invalid-operation", "Invalid picture position")
    }
  }
  guard value
    is {
      "horizontal": horizontal,
      "vertical": vertical,
      "behind": True
      | False,
      ..
    } else {
    @failure.reject("invalid-operation", "Invalid picture anchor")
  }
  let order = field_number(value, "order")
  guard order >= 0 && order <= 4294967295 && order == order.floor() else {
    @failure.reject("invalid-operation", "Invalid picture layer order")
  }
  Some({
    horizontal: axis(horizontal),
    vertical: axis(vertical),
    behind: value is { "behind": True, .. },
    order: order.to_int64(),
    wrapping: field_string(value, "wrapping"),
    wrapSide: field_string(value, "wrapSide"),
    distance: {
      guard value is { "distance": distance, .. } else {
        @failure.reject(
          "invalid-operation", "Picture text distance is required",
        )
      }
      {
        top: field_number(distance, "top"),
        right: field_number(distance, "right"),
        bottom: field_number(distance, "bottom"),
        left: field_number(distance, "left"),
      }
    },
  })
}

///|
fn resize_picture(
  session : @model.Session,
  revision : Int32,
  picture : Json,
  probe : @layout.TextProbe,
  profile : Map[String, String],
  images : @layout.Images,
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
  session.edit_picture(
    revision,
    field_int(picture, "id"),
    width,
    height,
    crop,
    probe~,
    profile~,
    images~,
  )
}
