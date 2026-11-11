///|
fn Context::docx_flow(
  self : Context,
  session : @model.Session,
) -> Json raise @failure.Failure {
  let flow = session.flow()
  self.images.retain(self.docx_image_keys(session, flow))
  flow.to_json()
}

///|
fn Context::docx_image_keys(
  self : Context,
  session : @model.Session,
  flow : @layout.Flow,
) -> Array[String] raise @failure.Failure {
  let keys : Array[String] = []
  fn retain(paragraph : @layout.Paragraph) {
    for span in paragraph.spans {
      if span.drawing is Some({ content: @layout.Metafile(file), .. }) {
        for key in file.image_keys() {
          if !keys.contains(key) {
            keys.push(key)
          }
        }
      }
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
    for paragraph in header.all_paragraphs() {
      retain(paragraph)
    }
  }
  for table in flow.tables {
    for paragraph in table.paragraphs() {
      retain(paragraph)
    }
  }
  for section in flow.sectionBreaks {
    for
      story in section.headers.values().to_array() +
      section.footers.values().to_array() {
      for paragraph in story.all_paragraphs() {
        retain(paragraph)
      }
    }
  }
  for note in flow.notes {
    for paragraph in note.content {
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
  if self.layout is Some(layout) && layout.revision == flow.revision {
    for page in layout.pages {
      for line in page.lines {
        for drawing in line.drawings {
          if drawing.content is @layout.Metafile(file) {
            for key in file.image_keys() {
              if !keys.contains(key) {
                keys.push(key)
              }
            }
          }
        }
      }
    }
  }
  keys
}

///|
priv struct DrawingGestureBeginRequest {
  drawing : @common.RequestInt
  handle : @common.RequestInt
} derive(@json.FromJson)

///|
priv struct DrawingGestureMoveRequest {
  id : @common.RequestInt
  dx : @common.RequestNumber
  dy : @common.RequestNumber
  page : @common.RequestInt?
} derive(@json.FromJson)

///|
priv struct PictureInsertRequest {
  width : @common.RequestNumber
  height : @common.RequestNumber
  bytes : String
} derive(@json.FromJson)

///|
priv struct PictureReplaceRequest {
  id : @common.RequestInt
  bytes : String
} derive(@json.FromJson)

///|
priv struct PictureResizeRequest {
  id : @common.RequestInt
  width : @common.RequestNumber
  height : @common.RequestNumber
  crop : Array[@common.RequestNumber]
} derive(@json.FromJson)

///|
priv struct PictureCommandRequest {
  revision : @common.RequestInt
  picture : Json?
  change : Json?
  profile : Json?
} derive(@json.FromJson)

///|
fn drawing_profile(
  profile : Json?,
) -> Map[String, String] raise @failure.Failure {
  font_profile(profile.unwrap_or(Json::null()))
}

///|
fn Context::edit_picture_command(
  self : Context,
  session : @model.Session,
  request : Json,
  gesture : Bool,
) -> Json raise @failure.Failure {
  let input : PictureCommandRequest = @common.request(request)
  let revision = input.revision.value
  if gesture {
    guard input.change is Some(change) else {
      @failure.reject(
        "invalid-operation", "Picture gesture command is required",
      )
    }
    let action : @common.ActionRequest = @common.request(change)
    let result = match action.action {
      "begin" => {
        let command : DrawingGestureBeginRequest = @common.request(change)
        session.begin_drawing_gesture(
          revision,
          command.drawing.value,
          command.handle.value,
          probe=self.probe,
          profile=drawing_profile(input.profile),
          images=self.images,
        )
      }
      "cancel" => {
        let command : DrawingIdRequest = @common.request(change)
        session.cancel_drawing_gesture(revision, command.id.value)
      }
      "update" | "commit" => {
        guard !(change is { "page": Null, .. }) else {
          @failure.reject("invalid-operation", "Invalid drawing gesture page")
        }
        let command : DrawingGestureMoveRequest = @common.request(change)
        let page = command.page.map(value => value.value)
        if action.action == "update" {
          session.update_drawing_gesture(
            revision,
            command.id.value,
            command.dx.value,
            command.dy.value,
            page?,
          )
        } else {
          session.finish_drawing_gesture(
            revision,
            command.id.value,
            command.dx.value,
            command.dy.value,
            page?,
          )
        }
      }
      _ =>
        @failure.reject("invalid-operation", "Unknown picture gesture command")
    }
    return self.clear_edit_layout(result)
  }
  guard input.picture is Some(picture) else {
    @failure.reject("invalid-operation", "Picture settings are required")
  }
  let action : @common.ActionRequest = @common.request(picture)
  let result = match action.action {
    "hyperlink" => drawing_hyperlink(session, revision, picture)
    "insert" => {
      let command : PictureInsertRequest = @common.request(picture)
      session.insert_picture(
        revision,
        command.width.value,
        command.height.value,
        @common.byte_input(command.bytes, @model.ImageInputBytes),
      )
    }
    "delete" => {
      let command : DrawingIdRequest = @common.request(picture)
      session.delete_picture(revision, command.id.value)
    }
    "replace" => {
      let command : PictureReplaceRequest = @common.request(picture)
      session.replace_picture(
        revision,
        command.id.value,
        @common.byte_input(command.bytes, @model.ImageInputBytes),
      )
    }
    "resize" => {
      let command : PictureResizeRequest = @common.request(picture)
      session.edit_picture(
        revision,
        command.id.value,
        command.width.value,
        command.height.value,
        command.crop.map(value => value.value),
        probe=self.probe,
        profile=drawing_profile(input.profile),
        images=self.images,
      )
    }
    "position" =>
      self.position_drawing(session, revision, picture, input.profile)
    _ => @failure.reject("invalid-operation", "Invalid picture action")
  }
  self.clear_edit_layout(result, previous=revision)
}

///|
priv struct DrawingIdRequest {
  id : @common.RequestInt
} derive(@json.FromJson)

///|
priv struct DrawingHyperlinkRequest {
  id : @common.RequestInt
  target : @common.RequiredNullable[String]
} derive(@json.FromJson)

///|
priv struct DrawingPositionRequest {
  id : @common.RequestInt
  anchor : @common.RequiredNullable[DrawingAnchorRequest]
  target : PositionRequest?
} derive(@json.FromJson)

///|
fn Context::position_drawing(
  self : Context,
  session : @model.Session,
  revision : Int32,
  change : Json,
  profile : Json?,
) -> Json raise @failure.Failure {
  let drawing : DrawingPositionRequest = @common.request(change)
  let anchor = drawing.anchor.value.map(anchor => anchor.anchor())
  guard !(change is { "target": Null, .. }) else {
    @failure.reject("invalid-operation", "Invalid drawing target position")
  }
  session.set_drawing_anchor(
    revision,
    drawing.id.value,
    anchor,
    target?=drawing.target.map(target => target.position()),
    probe=self.probe,
    profile=drawing_profile(profile),
    images=self.images,
  )
}

///|
fn drawing_hyperlink(
  session : @model.Session,
  revision : Int32,
  change : Json,
) -> Json raise @failure.Failure {
  let command : DrawingHyperlinkRequest = @common.request(change)
  session.set_drawing_hyperlink(
    revision,
    command.id.value,
    command.target.value,
  )
}

///|
priv struct DrawingAxisRequest {
  relativeTo : String
  offset : Json
  align : Json
} derive(@json.FromJson)

///|
fn DrawingAxisRequest::axis(
  self : DrawingAxisRequest,
) -> @layout.DrawingAxis raise @failure.Failure {
  match (self.offset, self.align) {
    (Number(offset, ..), Null) => @layout.Offset(self.relativeTo, offset)
    (Null, String(align)) => @layout.Aligned(self.relativeTo, align)
    _ => @failure.reject("invalid-operation", "Invalid picture position")
  }
}

///|
priv struct DrawingDistanceRequest {
  top : @common.RequestNumber
  right : @common.RequestNumber
  bottom : @common.RequestNumber
  left : @common.RequestNumber
} derive(@json.FromJson)

///|
priv struct DrawingAnchorRequest {
  horizontal : DrawingAxisRequest
  vertical : DrawingAxisRequest
  behind : Bool
  order : @common.RequestNumber
  wrapping : String
  wrapSide : String
  distance : DrawingDistanceRequest
} derive(@json.FromJson)

///|
fn DrawingAnchorRequest::anchor(
  anchor : DrawingAnchorRequest,
) -> @layout.DrawingAnchor raise @failure.Failure {
  let order = anchor.order.value
  guard order >= 0 && order <= 4294967295 && order == order.floor() else {
    @failure.reject("invalid-operation", "Invalid picture layer order")
  }
  {
    horizontal: anchor.horizontal.axis(),
    vertical: anchor.vertical.axis(),
    behind: anchor.behind,
    order: order.to_int64(),
    wrapping: anchor.wrapping,
    wrapSide: anchor.wrapSide,
    distance: {
      top: anchor.distance.top.value,
      right: anchor.distance.right.value,
      bottom: anchor.distance.bottom.value,
      left: anchor.distance.left.value,
    },
  }
}
