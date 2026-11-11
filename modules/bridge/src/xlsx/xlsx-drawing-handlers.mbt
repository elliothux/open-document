///|
let drawing_handlers : Map[
  String,
  (Context, @model.Session, Json) -> Json raise @failure.Failure,
] = {
  "captureDrawingXlsx": (context, session, input) => {
    let command : CaptureDrawingRequest = @common.request(input)
    session.capture_drawing(
      command.revision.value,
      command.sheet,
      command.objectId,
      context.probe,
      command.profile.value,
    )
  },
  "drawingFragmentImageXlsx": (context, session, input) => {
    let command : DrawingFragmentRequest = @common.request(input)
    let image = session.drawing_fragment_image(
      command.revision.value,
      command.fragment,
    )
    {
      "bytes": image
      .map(bytes => Json(context.output.add(bytes)))
      .unwrap_or(Json::null()),
    }
  },
  "pasteDrawingXlsx": (context, session, input) => {
    let command : PasteDrawingRequest = @common.request(input)
    session.paste_drawing(
      command.revision.value,
      command.sheet,
      command.fragment,
      context.probe,
      command.profile.value,
      images=context.images,
    )
  },
  "selectDrawingXlsx": (_context, session, input) => {
    let command : SelectDrawingRequest = @common.request(input)
    session.select_drawing(
      command.revision.value,
      command.layout.value,
      command.objectId.value,
    )
  },
  "drawingGestureXlsx": (context, session, input) => {
    let command : DrawingGestureRequest = @common.request(input)
    session.drawing_gesture(
      command.revision.value,
      command.layout.value,
      command.handle.value,
      command.dx.value,
      command.dy.value,
      command.commit,
      context.probe,
      command.profile.value,
      images=context.images,
      viewport=xlsx_drawing_viewport(input),
    )
  },
  "slicerGestureXlsx": (context, session, input) => {
    let command : SlicerGestureRequest = @common.request(input)
    session.slicer_gesture(
      command.revision.value,
      command.layout.value,
      command.objectId,
      command.first.value,
      command.position.value,
      command.x.value,
      command.y.value,
      command.additive,
      command.commit,
      context.probe,
      command.profile.value,
      images=context.images,
    )
  },
  "timelineGestureXlsx": (context, session, input) => {
    let command : TimelineGestureRequest = @common.request(input)
    session.timeline_gesture(
      command.revision.value,
      command.layout.value,
      command.objectId,
      command.handle.value,
      command.first.value,
      command.position.value,
      command.x.value,
      command.y.value,
      command.commit,
      context.probe,
      command.profile.value,
      images=context.images,
    )
  },
  "picturesXlsx": (context, session, input) => {
    let command : SheetProfileRequest = @common.request(input)
    session.pictures(
      command.revision.value,
      command.sheet,
      context.probe,
      command.profile.value,
    )
  },
  "pictureResourceXlsx": (context, session, input) => {
    let revision = @common.request_revision(input)
    let source : PictureResourceRequest = @common.request(input)
    session.picture_resource(
      revision,
      @common.byte_input(source.bytes, @model.ImageInputBytes),
      encode_pixels?=if source.preparePixels == Some(true) {
        Some(bytes => context.output.add(bytes))
      } else {
        None
      },
    )
  },
  "prepareImageXlsx": (context, session, input) => {
    let command : ImageKeyRequest = @common.request(input)
    let (source, image) = session.prepare_picture_image(
      command.revision.value,
      command.key,
      context.images,
    )
    @common.image_response(context.output, source, image)
  },
  "imageXlsx": (context, session, input) => {
    let command : ImagePixelsRequest = @common.request(input)
    session.register_picture_image(
      command.revision.value,
      command.key,
      command.width.value,
      command.height.value,
      @common.byte_input(command.bytes, @layout.ImageBytes),
      context.images,
    )
    { "key": context.images.get(command.key).identity }
  },
  "insertPictureXlsx": (context, session, input) => {
    let command : InsertPictureRequest = @common.request(input)
    session.insert_picture(
      command.revision.value,
      command.sheet,
      command.width.value,
      command.height.value,
      @common.byte_input(command.bytes, @model.ImageInputBytes),
      context.probe,
      command.profile.value,
      name=command.name,
      description=command.description,
      images=context.images,
    )
  },
  "replacePictureXlsx": (context, session, input) => {
    let command : ReplacePictureRequest = @common.request(input)
    session.replace_picture(
      command.revision.value,
      command.sheet,
      command.id,
      @common.byte_input(command.bytes, @model.ImageInputBytes),
      context.probe,
      command.profile.value,
      images=context.images,
    )
  },
  "setPictureXlsx": (context, session, input) => {
    let command : SetPictureRequest = @common.request(input)
    let settings = command.settings
    session.set_picture(
      command.revision.value,
      command.sheet,
      command.id,
      settings.anchor,
      {
        x: settings.x.value,
        y: settings.y.value,
        width: settings.width.value,
        height: settings.height.value,
      },
      settings.name,
      settings.description,
      context.probe,
      command.profile.value,
      crop=settings.crop.value,
    )
  },
  "deletePictureXlsx": (context, session, input) => {
    let command : ObjectIdRequest = @common.request(input)
    session.delete_picture(
      command.revision.value,
      command.sheet,
      command.id,
      context.probe,
      command.profile.value,
    )
  },
}

///|
#derive(@json.FromJson)
priv struct PictureResourceRequest {
  bytes : String
  preparePixels : Bool?
}
