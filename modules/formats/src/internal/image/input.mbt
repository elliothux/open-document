///|
pub const InputBytes : Int32 = 4194304

///|
fn image_uint(bytes : Bytes, offset : Int32, length : Int32) -> Int64 {
  let mut value = 0L
  for i = offset; i < offset + length; i = i + 1 {
    value = value * 256 + bytes[i].to_int().to_int64()
  }
  value
}

///|
pub fn type_info(
  bytes : Bytes,
) -> (String, String, Int32, Int32) raise @failure.Failure {
  guard bytes.length() <= InputBytes else {
    @failure.reject("limit-exceeded", "Image input exceeds budget")
  }
  guard @layout.raster_header(bytes) is Some((kind, width, height)) &&
    width > 0 &&
    height > 0 &&
    (
      (
        kind == "png" &&
        bytes.length() >= 45 &&
        bytes[bytes.length() - 12:bytes.length() - 4] == b"\x00\x00\x00\x00IEND"
      ) ||
      (kind == "jpeg" && bytes[bytes.length() - 2:] == b"\xff\xd9")
    ) else {
    @failure.reject("invalid-image", "Invalid PNG or JPEG image header")
  }
  @layout.check_raster_size(width, height)
  (
    if kind == "png" {
      "png"
    } else {
      "jpg"
    },
    "image/" + kind,
    width.to_int(),
    height.to_int(),
  )
}
