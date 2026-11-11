///|
priv struct TextSpecRequest {
  placement : PlacementRequest
  text : String
  font : String
  size : @common.RequestNumber
  color : String
  role : String
  foreground : Bool
} derive(@json.FromJson)

///|
fn TextSpecRequest::spec(self : TextSpecRequest) -> @model.PdfTextSpec {
  {
    placement: self.placement.placement(),
    text: self.text,
    font: self.font,
    size: self.size.value,
    color: self.color,
    role: self.role,
    foreground: self.foreground,
  }
}

///|
priv struct AddTextRequest {
  revision : @common.RequestInt
  pages : PdfPages
  spec : TextSpecRequest
  profile : @common.RequestProfile
} derive(@json.FromJson)

///|
priv struct ReplaceTextRequest {
  revision : @common.RequestInt
  page : String
  object : String
  spec : TextSpecRequest
  profile : @common.RequestProfile
} derive(@json.FromJson)

///|
priv struct ImageAddRequest {
  bytes : String
  revision : @common.RequestInt
  page : String
  placement : PlacementRequest
  pixelWidth : @common.RequestInt
  pixelHeight : @common.RequestInt
  profile : @common.RequestProfile
  replace : String?
} derive(@json.FromJson)

///|
priv struct MoveObjectRequest {
  revision : @common.RequestInt
  page : String
  object : String
  placement : PlacementRequest
  profile : @common.RequestProfile
} derive(@json.FromJson)

///|
priv struct ObjectRequest {
  revision : @common.RequestInt
  page : String
  object : String
  profile : @common.RequestProfile
} derive(@json.FromJson)

///|
priv struct CropImageRequest {
  revision : @common.RequestInt
  page : String
  object : String
  crop : CropWindowRequest
  profile : @common.RequestProfile
} derive(@json.FromJson)

///|
let object_handlers : Map[
  String,
  (Context, @model.PdfSession, Json) -> String raise @failure.Failure,
] = {
  "pdfObjects": (context, session, input) => {
    let command : PageReadRequest = @common.request(input)
    let result = session.objects(
      command.revision.value,
      command.page,
      context.probe,
      command.profile.value,
    )
    ToJson::to_json(result).stringify()
  },
  "addPdfText": (context, session, input) => {
    let command : AddTextRequest = @common.request(input)
    session
    .add_text(
      command.revision.value,
      command.pages.value,
      command.spec.spec(),
      context.probe,
      command.profile.value,
    )
    .stringify()
  },
  "setPdfPageNumbers": (context, session, input) => {
    let command : AddTextRequest = @common.request(input)
    session
    .add_text(
      command.revision.value,
      command.pages.value,
      command.spec.spec(),
      context.probe,
      command.profile.value,
      replace_numbers=true,
    )
    .stringify()
  },
  "replacePdfText": (context, session, input) => {
    let command : ReplaceTextRequest = @common.request(input)
    session
    .replace_text(
      command.revision.value,
      command.page,
      command.object,
      command.spec.spec(),
      context.probe,
      command.profile.value,
    )
    .stringify()
  },
  "addPdfImage": (context, session, input) => {
    if input is { "replace": Null, .. } {
      @failure.reject(
        "invalid-operation", "PDF image replacement identity must be text",
      )
    }
    let command : ImageAddRequest = @common.request(input)
    session
    .add_image(
      command.revision.value,
      command.page,
      command.placement.placement(),
      command.pixelWidth.value,
      command.pixelHeight.value,
      @common.byte_input(command.bytes, @layout.ImageBytes),
      context.probe,
      command.profile.value,
      replace=command.replace.unwrap_or(""),
    )
    .stringify()
  },
  "movePdfObject": (context, session, input) => {
    let command : MoveObjectRequest = @common.request(input)
    session
    .move_object(
      command.revision.value,
      command.page,
      command.object,
      command.placement.placement(),
      context.probe,
      command.profile.value,
    )
    .stringify()
  },
  "cropPdfImage": (context, session, input) => {
    let command : CropImageRequest = @common.request(input)
    session
    .crop_image(
      command.revision.value,
      command.page,
      command.object,
      command.crop.crop(),
      context.probe,
      command.profile.value,
    )
    .stringify()
  },
  "deletePdfObject": (context, session, input) => {
    let command : ObjectRequest = @common.request(input)
    session
    .delete_object(
      command.revision.value,
      command.page,
      command.object,
      context.probe,
      command.profile.value,
    )
    .stringify()
  },
}
