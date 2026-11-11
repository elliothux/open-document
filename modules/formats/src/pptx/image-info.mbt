///|
pub const ImageInputBytes : Int32 = @image.InputBytes

///|
pub fn verifies_upload_raster(bytes : Bytes) -> Bool {
  @image.decode_plain_raster(bytes, exif_orientation=true) is Some(_)
}

///|
fn raster_image_info(
  bytes : Bytes,
) -> (String, String, Int32, Int32) raise @failure.Failure {
  if bytes.length() < 6 || (bytes[0:6] != b"GIF87a" && bytes[0:6] != b"GIF89a") {
    return @image.type_info(bytes)
  }
  guard bytes.length() <= ImageInputBytes else {
    @failure.reject("limit-exceeded", "Image input exceeds budget")
  }
  guard bytes.length() >= 14 && bytes[bytes.length() - 1] == b'\x3b' else {
    @failure.reject("invalid-image", "Invalid GIF image header or trailer")
  }
  guard @layout.raster_header(bytes) is Some((_, width, height)) &&
    width > 0 &&
    height > 0 else {
    @failure.reject("invalid-image", "Invalid GIF image dimensions")
  }
  @layout.check_raster_size(width, height)
  ("gif", "image/gif", width.to_int(), height.to_int())
}
