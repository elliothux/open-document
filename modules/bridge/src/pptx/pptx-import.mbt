///|
priv struct ImportRequest {
  revision : @common.RequestInt
  after : String
  profile : @common.RequestProfile
} derive(@json.FromJson)

///|
priv struct InspectImportRequest {
  revision : @common.RequestInt
  prepareResources : Json?
  prepareImages : Json?
  verifyImages : Json?
} derive(@json.FromJson)

///|
fn pptx_import_source(
  request : Json,
) -> (Array[Int32], Bytes) raise @failure.Failure {
  guard request is { "indices": Array(values), .. } &&
    values.length() <= @model.SlideCountLimit else {
    @failure.reject(
      "invalid-slide", "Explicit bounded source slide indices are required",
    )
  }
  let indices = values.map(value => {
    let index : @common.RequestInt = @json.from_json(value) catch {
      @json.JsonDecodeError(_) =>
        @failure.reject("invalid-slide", "Invalid source slide index")
    }
    guard index.value < @model.SlideCountLimit else {
      @failure.reject("invalid-slide", "Invalid source slide index")
    }
    index.value
  })
  let source : @common.BytesRequest = @common.request(request)
  (indices, @common.byte_input(source.bytes, @model.SlideImportBytes))
}

///|
let import_handlers : Map[
  String,
  (Context, @model.Session, Json) -> Json raise @failure.Failure,
] = {
  "inspectPptxSlides": (context, session, input) => {
    let (indices, bytes) = pptx_import_source(input)
    let command : InspectImportRequest = @common.request(input)
    let prepare_images = command.prepareResources is Some(True) ||
      command.prepareImages is Some(True)
    let verify = if command.verifyImages is Some(True) {
      Some(@model.verifies_upload_raster)
    } else {
      None
    }
    session.import_slide_info(
      command.revision.value,
      bytes,
      indices,
      encode_image=bytes => {
        if prepare_images {
          @common.image_response(context.output, bytes, None, verify?)
        } else {
          Json(context.output.add(bytes))
        }
      },
      encode_media=bytes => Json(context.output.add(bytes)),
    )
  },
  "importPptxSlides": (context, session, input) => {
    let (indices, bytes) = pptx_import_source(input)
    let command : ImportRequest = @common.request(input)
    session.import_slides(
      command.revision.value,
      bytes,
      indices,
      command.after,
      context.probe,
      command.profile.value,
    )
  },
}
