///|
pub(all) enum ImageHeader {
  ImageDimensions(Int32, Int32, transpose~ : Bool, verified~ : Bool)
  ImageReadAt(Int64)
  ImageError(String)
}

///|
priv struct ImageDimensionsOutput {
  width : Int32
  height : Int32
  allowTranspose : Bool?
  coreVerified : Bool?
} derive(ToJson)

///|
pub impl ToJson for ImageHeader with fn to_json(self) {
  match self {
    ImageDimensions(width, height, transpose~, verified~) => {
      let value : ImageDimensionsOutput = {
        width,
        height,
        allowTranspose: if transpose {
          Some(true)
        } else {
          None
        },
        coreVerified: if verified {
          Some(true)
        } else {
          None
        },
      }
      ToJson::to_json(value)
    }
    ImageReadAt(offset) => { "nextOffset": offset.to_double() }
    ImageError(error) => { "error": error }
  }
}

///|
pub extend ImageHeader with ToJson::{to_json}

///|
priv struct RgbaImageOutput {
  kind : String
  key : String
  width : Int32
  height : Int32
  bytes : Int32
} derive(ToJson)

///|
priv struct EncodedImageOutput {
  kind : String
  bytes : Int32
  header : ImageHeader
} derive(ToJson)

///|
pub fn image_response(
  output : OutputBytes,
  source : Bytes,
  prepared : @layout.ImageResource?,
  verify? : (Bytes) -> Bool,
) -> Json {
  match prepared {
    Some(image) => {
      let value : RgbaImageOutput = {
        kind: "rgba",
        key: image.identity,
        width: image.width,
        height: image.height,
        bytes: output.add(image.rgba),
      }
      ToJson::to_json(value)
    }
    None => {
      let value : EncodedImageOutput = {
        kind: "encoded",
        bytes: output.add(source),
        header: image_header_window(
          source,
          0L,
          source.length().to_int64(),
          office=true,
          verify?,
        ),
      }
      ToJson::to_json(value)
    }
  }
}

///|
pub fn image_header(source : Bytes) -> ImageHeader {
  image_header_window(source, 0L, source.length().to_int64())
}

///|
priv struct OfficeUploadRequest {
  bytes : String
  verify : Bool?
} derive(@json.FromJson)

///|
pub fn office_upload_header(
  input : Json,
  limit : Int32,
  verify : (Bytes) -> Bool,
) -> Json raise @failure.Failure {
  let command : OfficeUploadRequest = request(input)
  let bytes = byte_input(command.bytes, limit)
  let verify = if command.verify == Some(true) { Some(verify) } else { None }
  image_header_window(
    bytes,
    0L,
    bytes.length().to_int64(),
    office=true,
    verify?,
  ).to_json()
}

///|
pub fn image_header_window(
  source : Bytes,
  offset : Int64,
  total : Int64,
  office~ : Bool = false,
  verify? : (Bytes) -> Bool,
) -> ImageHeader {
  let scan = @layout.raster_header_window(source, offset, total)
  if scan is @layout.RasterReadAt(next) {
    return ImageReadAt(next)
  }
  guard scan is @layout.RasterDimensions(kind, width, height) &&
    width > 0 &&
    height > 0 else {
    return ImageError("Unsupported or malformed PNG, JPEG or GIF image header")
  }
  try @layout.check_raster_size(width, height) catch {
    @failure.Failure(message~, ..) => ImageError(message)
  } noraise {
    _ =>
      ImageDimensions(
        width.to_int(),
        height.to_int(),
        transpose=office && kind == "jpeg",
        verified=verify.map(check => check(source)).unwrap_or(false),
      )
  }
}
