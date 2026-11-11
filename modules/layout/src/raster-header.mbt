///|
fn raster_uint(bytes : Bytes, offset : Int32, length : Int32) -> Int64 {
  let mut value = 0L
  for i = offset; i < offset + length; i = i + 1 {
    value = value * 256 + bytes[i].to_int().to_int64()
  }
  value
}

///|
pub(all) enum RasterHeaderScan {
  RasterDimensions(String, Int64, Int64)
  RasterReadAt(Int64)
  InvalidRasterHeader
}

///|
/// Read dimensions only. Insertion still validates format-specific file boundaries.
pub fn raster_header(bytes : Bytes) -> (String, Int64, Int64)? {
  match raster_header_window(bytes, 0L, bytes.length().to_int64()) {
    RasterDimensions(kind, width, height) => Some((kind, width, height))
    _ => None
  }
}

///|
/// Walk JPEG markers without retaining or transferring their skipped payloads.
pub fn raster_header_window(
  bytes : Bytes,
  offset : Int64,
  total : Int64,
) -> RasterHeaderScan {
  let size = bytes.length()
  let end = offset + size.to_int64()
  let mut cursor = offset
  if offset == 0L {
    if size >= 33 &&
      bytes[0:8] == b"\x89PNG\x0d\x0a\x1a\x0a" &&
      raster_uint(bytes, 8, 4) == 13 &&
      bytes[12:16] == b"IHDR" {
      return RasterDimensions(
        "png",
        raster_uint(bytes, 16, 4),
        raster_uint(bytes, 20, 4),
      )
    }
    if size >= 13 && (bytes[0:6] == b"GIF87a" || bytes[0:6] == b"GIF89a") {
      let width = raster_uint(bytes, 6, 1) + 256L * raster_uint(bytes, 7, 1)
      let height = raster_uint(bytes, 8, 1) + 256L * raster_uint(bytes, 9, 1)
      return RasterDimensions("gif", width, height)
    }
    guard size >= 4 && bytes[0:2] == b"\xff\xd8" else {
      return InvalidRasterHeader
    }
    cursor = 2L
  }
  while cursor <= total - 4L {
    if cursor >= end {
      return RasterReadAt(cursor)
    }
    guard bytes[(cursor - offset).to_int()] == b'\xff' else { break }
    cursor += 1L
    while cursor < end && bytes[(cursor - offset).to_int()] == b'\xff' {
      cursor += 1L
    }
    guard cursor <= total - 3L else { break }
    if cursor == end {
      return RasterReadAt(cursor - 1L)
    }
    let marker_at = cursor - 1L
    let marker = bytes[(cursor - offset).to_int()].to_int()
    cursor += 1L
    if marker == 0xda || marker == 0xd9 {
      break
    }
    if marker == 1 || (marker >= 0xd0 && marker <= 0xd7) {
      continue
    }
    if cursor + 2L > end {
      return RasterReadAt(marker_at)
    }
    let position = (cursor - offset).to_int()
    let length = raster_uint(bytes, position, 2)
    guard length >= 2L && length <= total - cursor else { break }
    if marker >= 0xc0 &&
      marker <= 0xcf &&
      marker != 0xc4 &&
      marker != 0xc8 &&
      marker != 0xcc &&
      length >= 8L {
      if cursor + 7L > end {
        return RasterReadAt(marker_at)
      }
      return RasterDimensions(
        "jpeg",
        raster_uint(bytes, position + 5, 2),
        raster_uint(bytes, position + 3, 2),
      )
    }
    cursor += length
  }
  InvalidRasterHeader
}

///|
pub fn check_raster_size(
  width : Int64,
  height : Int64,
) -> Unit raise @failure.Failure {
  guard width <= ImageDimension.to_int64() &&
    height <= ImageDimension.to_int64() &&
    width * height <= (ImageBytes / 4).to_int64() else {
    @failure.reject("limit-exceeded", "Decoded image exceeds budget")
  }
}
