///|
#derive(@json.FromJson)
priv struct ProfileRequest {
  profile : @common.RequestProfile
}

///|
#derive(@json.FromJson)
priv struct PrintRequest {
  revision : @common.RequestInt
  all : Bool
  hidden : Bool
  profile : @common.RequestProfile
}

///|
#derive(@json.FromJson)
priv struct PdfExportRequest {
  outputBytes : @common.RequestInt
}

///|
#derive(@json.FromJson)
priv struct HitRequest {
  layoutId : @common.RequestInt
  x : @common.RequestNumber
  y : @common.RequestNumber
  tolerance : @common.RequestNumber
  text : Bool?
}

///|
#derive(@json.FromJson)
priv struct GeometryRequest {
  layoutId : @common.RequestInt
  gridScale : @common.RequestNumber?
}

///|
#derive(@json.FromJson(fields(extend_flag(rename="extend"))))
priv struct NavigateRequest {
  revision : @common.RequestInt
  layoutId : @common.RequestInt
  direction : String
  extend_flag : Bool
}

///|
#derive(@json.FromJson)
priv struct ResourceKeyRequest {
  key : String
  preview : String?
}

///|
#derive(@json.FromJson)
priv struct ImageRequest {
  bytes : String
  key : String
  width : @common.RequestInt
  height : @common.RequestInt
  preview : String?
}

///|
#derive(@json.FromJson)
priv struct PreviewTargetRequest {
  revision : @common.RequestInt
  slide : String
}

///|
#derive(@json.FromJson)
priv struct ImageKeysRequest {
  all : Bool
  hidden : Bool
}

///|
fn Context::retain_image_keys(
  self : Context,
  session : @model.Session,
  keys : Array[String],
) -> Json raise @failure.Failure {
  let retained = keys.copy()
  for key in session.image_keys(false, false) + session.show_image_keys() {
    if !retained.contains(key) {
      retained.push(key)
    }
  }
  guard retained.length() <= 256 else {
    @failure.reject("limit-exceeded", "Presentation images exceed 256")
  }
  // Keep the editor's current images while the slideshow prepares other pages.
  self.images.retain(retained)
  Json(keys)
}

///|
let view_handlers : Map[
  String,
  (Context, @model.Session, Json) -> Json raise @failure.Failure,
] = {
  "queryPptx": (_context, session, _input) => session.query(),
  "savePptx": (context, session, input) => {
    let revision = @common.request_revision(input)
    { "bytes": context.output.add(session.save(revision)) }
  },
  "layoutPptx": (context, session, input) => {
    let command : ProfileRequest = @common.request(input)
    session.layout(context.probe, command.profile.value, context.images)
  },
  "printLayoutPptx": (context, session, input) => {
    let command : PrintRequest = @common.request(input)
    session.print_drawing(
      command.revision.value,
      command.all,
      command.hidden,
      context.probe,
      command.profile.value,
      context.images,
    )
  },
  "exportPptxPdf": (context, session, input) => {
    let command : PrintRequest = @common.request(input)
    let document = session.print_layout(
      command.revision.value,
      command.all,
      command.hidden,
      context.probe,
      command.profile.value,
    )
    let output : PdfExportRequest = @common.request(input)
    {
      "bytes": context.output.add(
        @pdf.write(
          document,
          context.probe,
          context.images,
          output.outputBytes.value,
        ),
      ),
    }
  },
  "hitPptx": (_context, session, input) => {
    let command : HitRequest = @common.request(input)
    session.hit(
      command.layoutId.value,
      command.x.value,
      command.y.value,
      command.tolerance.value,
      text=command.text.unwrap_or(false),
    )
  },
  "selectionPptx": (_context, session, input) => {
    let command : GeometryRequest = @common.request(input)
    session.selection_geometry(
      command.layoutId.value,
      grid_scale=command.gridScale.map(value => value.value),
    )
  },
  "navigatePptx": (_context, session, input) => {
    let command : NavigateRequest = @common.request(input)
    session.navigate(
      command.revision.value,
      command.layoutId.value,
      command.direction,
      command.extend_flag,
    )
  },
  "mediaBytesPptx": (context, session, input) => {
    let command : ResourceKeyRequest = @common.request(input)
    { "bytes": context.output.add(session.media_bytes(command.key)) }
  },
  "prepareImagePptx": (context, session, input) => {
    let command : ResourceKeyRequest = @common.request(input)
    let preview = command.preview
    let images = if preview is Some(_) {
      context.preview_images
    } else {
      context.images
    }
    let (source, image) = session.prepare_image(command.key, images, preview?)
    @common.image_response(context.output, source, image)
  },
  "imagePptx": (context, session, input) => {
    let command : ImageRequest = @common.request(input)
    let preview = command.preview
    let images = if preview is Some(_) {
      context.preview_images
    } else {
      context.images
    }
    ignore(session.image_bytes(command.key, preview?))
    images.add(
      command.key,
      command.width.value,
      command.height.value,
      @common.byte_input(command.bytes, @layout.ImageBytes),
    )
    if preview is None {
      session.invalidate_geometry()
    }
    { "key": images.get(command.key).identity }
  },
  "previewKeysPptx": (context, session, input) => {
    let target : PreviewTargetRequest = @common.request(input)
    context.preview_images.clear()
    Json(session.preview_keys(target.revision.value, target.slide))
  },
  "previewPptx": (context, session, input) => {
    let target : PreviewTargetRequest = @common.request(input)
    let command : ProfileRequest = @common.request(input)
    defer context.preview_images.clear()
    session.preview_drawing(
      target.revision.value,
      target.slide,
      context.probe,
      command.profile.value,
      context.preview_images,
    )
  },
  "imageKeysPptx": (context, session, input) => {
    let command : ImageKeysRequest = @common.request(input)
    context.retain_image_keys(
      session,
      session.image_keys(command.all, command.hidden),
    )
  },
  "imageKeysShowPptx": (context, session, _input) => {
    context.retain_image_keys(session, session.show_image_keys())
  },
}
