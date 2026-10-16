///|
fn image_uint(bytes : Bytes, offset : Int, length : Int) -> Int64 {
  let mut value = 0L
  for i = offset; i < offset + length; i = i + 1 {
    value = value * 256 + bytes[i].to_int().to_int64()
  }
  value
}

///|
fn image_type(bytes : Bytes) -> (String, String) raise @failure.Failure {
  guard bytes.length() <= 4194304 else {
    @failure.reject("limit-exceeded", "Image input exceeds budget")
  }
  let mut width = 0L
  let mut height = 0L
  let mut kind = ""
  if bytes.length() >= 45 &&
    bytes[0:8] == b"\x89PNG\x0d\x0a\x1a\x0a" &&
    image_uint(bytes, 8, 4) == 13 &&
    bytes[12:16] == b"IHDR" &&
    bytes[bytes.length() - 12:bytes.length() - 4] == b"\x00\x00\x00\x00IEND" {
    width = image_uint(bytes, 16, 4)
    height = image_uint(bytes, 20, 4)
    kind = "png"
  } else if bytes.length() >= 4 &&
    bytes[0:2] == b"\xff\xd8" &&
    bytes[bytes.length() - 2:] == b"\xff\xd9" {
    let mut offset = 2
    while offset + 4 <= bytes.length() {
      guard bytes[offset] == b'\xff' else { break }
      offset += 1
      while offset < bytes.length() && bytes[offset] == b'\xff' {
        offset += 1
      }
      guard offset + 3 <= bytes.length() else { break }
      let marker = bytes[offset].to_int()
      offset += 1
      if marker == 0xda || marker == 0xd9 {
        break
      }
      if marker == 1 || (marker >= 0xd0 && marker <= 0xd7) {
        continue
      }
      let length = image_uint(bytes, offset, 2).to_int()
      guard length >= 2 && length <= bytes.length() - offset else { break }
      if marker >= 0xc0 &&
        marker <= 0xcf &&
        marker != 0xc4 &&
        marker != 0xc8 &&
        marker != 0xcc &&
        length >= 8 {
        height = image_uint(bytes, offset + 3, 2)
        width = image_uint(bytes, offset + 5, 2)
        kind = "jpeg"
        break
      }
      offset += length
    }
  }
  guard !kind.is_empty() && width > 0 && height > 0 else {
    @failure.reject("invalid-image", "Invalid PNG or JPEG image header")
  }
  guard width <= 4096 && height <= 4096 && width * height <= 4194304 else {
    @failure.reject("limit-exceeded", "Decoded image exceeds budget")
  }
  (if kind == "png" { "png" } else { "jpg" }, "image/" + kind)
}
