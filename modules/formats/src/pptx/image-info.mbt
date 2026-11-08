///|
fn raster_image_info(
  bytes : Bytes,
) -> (String, String, Int32, Int32) raise @failure.Failure {
  if bytes.length() < 6 || (bytes[0:6] != b"GIF87a" && bytes[0:6] != b"GIF89a") {
    return @image.type_info(bytes)
  }
  guard bytes.length() <= 4194304 else {
    @failure.reject("limit-exceeded", "Image input exceeds budget")
  }
  guard bytes.length() >= 14 && bytes[bytes.length() - 1] == b'\x3b' else {
    @failure.reject("invalid-image", "Invalid GIF image header or trailer")
  }
  let width = bytes[6].to_int() | (bytes[7].to_int() << 8)
  let height = bytes[8].to_int() | (bytes[9].to_int() << 8)
  guard width > 0 && height > 0 else {
    @failure.reject("invalid-image", "Invalid GIF image dimensions")
  }
  guard width <= 4096 && height <= 4096 && width * height <= 4194304 else {
    @failure.reject("limit-exceeded", "Decoded image exceeds budget")
  }
  ("gif", "image/gif", width, height)
}
