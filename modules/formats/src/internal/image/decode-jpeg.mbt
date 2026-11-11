///|
fn tiff_exif_orientation(bytes : Bytes, tiff : Int32, end : Int32) -> Int32? {
  let length = end - tiff
  guard length >= 14 else { return None }
  let little = match bytes[tiff:tiff + 4] {
    b"II\x2a\x00" => true
    b"MM\x00\x2a" => false
    _ => return None
  }
  let read = fn(at : Int32, size : Int32) -> Int64 {
    let mut value = 0L
    for i in 0..<size {
      let index = if little { at + size - i - 1 } else { at + i }
      value = value * 256 + bytes[tiff + index].to_int().to_int64()
    }
    value
  }
  let mut orientation : Int32? = None
  let directory = fn(offset : Int64, root : Bool) -> Int64? {
    guard offset >= 8 && offset <= (length - 6).to_int64() else { return None }
    let at = offset.to_int()
    let count = read(at, 2).to_int()
    guard count <= (length - at - 6) / 12 else { return None }
    // Linked directories can carry metadata for other images.
    guard read(at + 2 + count * 12, 4) == 0 else { return None }
    let directory_end = at + 6 + count * 12
    let mut sub = 0L
    let mut density_tags = 0
    for i in 0..<count {
      let entry = at + 2 + i * 12
      match read(entry, 2).to_int() {
        0x0112 | 0xa001 as tag => {
          guard read(entry + 2, 2) == 3 && read(entry + 4, 4) == 1 else {
            return None
          }
          let value = read(entry + 8, 2).to_int()
          if tag == 0x0112 {
            guard (root || value == 1) &&
              value >= 1 &&
              value <= 8 &&
              orientation.unwrap_or(value) == value else {
              return None
            }
            orientation = Some(value)
          } else {
            guard value == 1 else { return None }
          }
        }
        0x8769 => {
          guard root &&
            sub == 0 &&
            read(entry + 2, 2) == 4 &&
            read(entry + 4, 4) == 1 else {
            return None
          }
          sub = read(entry + 8, 4)
          guard sub > offset else { return None }
        }
        0x011a | 0x011b as tag => {
          let bit = if tag == 0x011a { 1 } else { 2 }
          let ratio = read(entry + 8, 4)
          guard root &&
            (density_tags & bit) == 0 &&
            read(entry + 2, 2) == 5 &&
            read(entry + 4, 4) == 1 &&
            ratio >= directory_end.to_int64() &&
            ratio <= (length - 8).to_int64() else {
            return None
          }
          let numerator = read(ratio.to_int(), 4)
          let denominator = read(ratio.to_int() + 4, 4)
          // At Chromium's default 72 dpi the density-corrected size is unchanged.
          guard denominator > 0 && numerator == denominator * 72 else {
            return None
          }
          density_tags = density_tags | bit
        }
        0x0128 => {
          guard root &&
            (density_tags & 4) == 0 &&
            read(entry + 2, 2) == 3 &&
            read(entry + 4, 4) == 1 &&
            read(entry + 8, 2) == 2 else {
            return None
          }
          density_tags = density_tags | 4
        }
        0x014a | 0x927c => return None
        _ => ()
      }
    }
    guard density_tags == 0 || density_tags == 7 else { return None }
    Some(sub)
  }
  guard directory(read(4, 4), true) is Some(sub) else { return None }
  if sub != 0 {
    guard directory(sub, false) is Some(0L) else { return None }
  }
  Some(orientation.unwrap_or(1))
}

///|
fn orient_raster(
  width : Int32,
  height : Int32,
  pixels : Bytes,
  orientation : Int32,
) -> (Int32, Int32, Bytes) {
  if orientation == 1 {
    return (width, height, pixels)
  }
  let (out_width, out_height) = if orientation >= 5 {
    (height, width)
  } else {
    (width, height)
  }
  let oriented = Bytes::makei(pixels.length(), byte => {
    let x = byte / 4 % out_width
    let y = byte / 4 / out_width
    let (sx, sy) = match orientation {
      2 => (width - 1 - x, y)
      3 => (width - 1 - x, height - 1 - y)
      4 => (x, height - 1 - y)
      5 => (y, x)
      6 => (y, height - 1 - x)
      7 => (width - 1 - y, height - 1 - x)
      _ => (width - 1 - y, x)
    }
    pixels[(sy * width + sx) * 4 + byte % 4]
  })
  (out_width, out_height, oriented)
}

///|
/// Decode JPEG only when the browser would use the default grayscale or YCbCr path.
fn decode_plain_jpeg(
  bytes : Bytes,
  exif_orientation : Bool,
) -> (Int32, Int32, Bytes)? {
  let (_, _, width, height) = type_info(bytes) catch { _ => return None }
  let mut exif : Int32? = None
  for offset = 2; offset < bytes.length(); {
    guard bytes[offset] == b'\xff' else { return None }
    let mut marker = offset + 1
    while marker < bytes.length() && bytes[marker] == b'\xff' {
      marker += 1
    }
    guard marker + 2 < bytes.length() else { return None }
    let length = image_uint(bytes, marker + 1, 2).to_int()
    guard length >= 2 && length <= bytes.length() - marker - 1 else {
      return None
    }
    let start = marker + 3
    let end = marker + 1 + length
    match bytes[marker] {
      b'\xda' => break
      b'\xe0' =>
        if end - start < 5 || bytes[start:start + 5] != b"JFIF\x00" {
          return None
        }
      b'\xe1' => {
        guard exif is None &&
          end - start >= 6 &&
          bytes[start:start + 6] == b"Exif\x00\x00" &&
          tiff_exif_orientation(bytes, start + 6, end) is Some(orientation) &&
          (exif_orientation || orientation == 1) else {
          return None
        }
        exif = Some(orientation)
      }
      b'\xee' =>
        if end - start != 12 ||
          bytes[start:start + 5] != b"Adobe" ||
          bytes[start + 11] != b'\x01' {
          return None
        }
      b'\xc0' | b'\xc2' =>
        if end - start != 9 &&
          (
            end - start != 15 ||
            bytes[start + 6] != b'\x01' ||
            bytes[start + 9] != b'\x02' ||
            bytes[start + 12] != b'\x03'
          ) {
          return None
        }
      // shortcut: Keep ICC and other APP metadata on the host until the core
      // can reproduce the browser's interpretation.
      byte if byte >= b'\xe2' && byte <= b'\xef' => return None
      _ => ()
    }
    continue end
  }
  let image = @raster.decode_jpeg(bytes, inverse=jpeg_idct).to_rgba8() catch {
    _ => return None
  }
  guard image.width == width &&
    image.height == height &&
    image.data.length() == width * height * 4 else {
    return None
  }
  Some(orient_raster(width, height, image.data, exif.unwrap_or(1)))
}

///|
/// Prepare PNG or JPEG pixels when source color and raster rules are supported.
pub fn decode_plain_raster(
  bytes : Bytes,
  exif_orientation~ : Bool = false,
) -> (Int32, Int32, Bytes)? {
  if bytes.length() >= 2 && bytes[0:2] == b"\xff\xd8" {
    decode_plain_jpeg(bytes, exif_orientation)
  } else {
    decode_plain_png(bytes, exif_orientation)
  }
}
