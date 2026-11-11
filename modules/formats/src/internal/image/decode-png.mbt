///|
fn png_chunk_crc_valid(bytes : Bytes, offset : Int32, size : Int32) -> Bool {
  let end = offset + 8 + size
  let checksum = @checksum.Crc32()
  checksum.update(bytes[offset + 4:end])
  checksum.finish().to_int64() == image_uint(bytes, end, 4)
}

///|
/// Decode bounded PNGs whose samples can be rendered without color conversion.
fn decode_plain_png(
  bytes : Bytes,
  exif_orientation : Bool,
) -> (Int32, Int32, Bytes)? {
  guard bytes.length() >= 45 && bytes[0:8] == b"\x89PNG\x0d\x0a\x1a\x0a" else {
    return None
  }
  let (_, _, width, height) = type_info(bytes) catch { _ => return None }
  if bytes[24] == b'\x10' {
    let channels = match bytes[25] {
      b'\x00' => 1
      b'\x02' => 3
      b'\x04' => 2
      b'\x06' => 4
      _ => return None
    }
    // Keep the inflated sample allocation within the existing raster budget.
    guard width * height * channels * 2 <= @layout.ImageBytes else {
      return None
    }
  }
  // shortcut: Defer color, animation and other ancillary metadata to the
  // host until the core can reproduce its raster output.
  let mut srgb = false
  let mut cicp = false
  let mut gamma = false
  let mut chromaticities = false
  let mut significant_bits = false
  let mut before_palette = true
  let mut palette_size = 0L
  let mut histogram = false
  let mut image_data = false
  let mut exif : Int32? = None
  for offset = 8; offset <= bytes.length() - 12; {
    let size = image_uint(bytes, offset, 4)
    guard size <= (bytes.length() - offset - 12).to_int64() else { return None }
    match bytes[offset + 4:offset + 8] {
      b"IHDR" | b"tRNS" | b"pHYs" | b"tEXt" | b"zTXt" | b"iTXt" => ()
      b"PLTE" => {
        before_palette = false
        palette_size = size
      }
      b"IDAT" => {
        before_palette = false
        image_data = true
      }
      b"tIME" => {
        guard size == 7 && png_chunk_crc_valid(bytes, offset, 7) else {
          return None
        }
      }
      b"bKGD" => {
        let length = match bytes[25] {
          b'\x00' | b'\x04' => 2
          b'\x02' | b'\x06' => 6
          b'\x03' => 1
          _ => return None
        }
        guard !image_data &&
          size == length.to_int64() &&
          png_chunk_crc_valid(bytes, offset, length) else {
          return None
        }
      }
      b"hIST" => {
        guard !image_data &&
          !histogram &&
          palette_size >= 3 &&
          palette_size <= 768 &&
          palette_size % 3 == 0 &&
          size == palette_size / 3 * 2 &&
          png_chunk_crc_valid(bytes, offset, size.to_int()) else {
          return None
        }
        histogram = true
      }
      b"eXIf" => {
        let start = offset + 8
        guard !image_data &&
          exif is None &&
          png_chunk_crc_valid(bytes, offset, size.to_int()) &&
          tiff_exif_orientation(bytes, start, start + size.to_int())
          is Some(orientation) &&
          (exif_orientation || orientation == 1) else {
          return None
        }
        exif = Some(orientation)
      }
      b"sBIT" => {
        let color = bytes[25]
        let channels = match color {
          b'\x00' => 1
          b'\x02' | b'\x03' => 3
          b'\x04' => 2
          b'\x06' => 4
          _ => return None
        }
        let maximum = if color == b'\x03' { b'\x08' } else { bytes[24] }
        guard before_palette &&
          !significant_bits &&
          size == channels.to_int64() &&
          png_chunk_crc_valid(bytes, offset, channels) &&
          bytes[offset + 8:offset + 8 + channels]
          .iter()
          .all(bits => bits > b'\x00' && bits <= maximum) else {
          return None
        }
        // The stored samples already use the PNG output depth.
        significant_bits = true
      }
      b"cICP" => {
        // Full-range sRGB uses BT.709 primaries and identity RGB coefficients.
        guard before_palette &&
          !cicp &&
          size == 4 &&
          bytes[offset + 8:offset + 12] == b"\x01\x0d\x00\x01" &&
          png_chunk_crc_valid(bytes, offset, 4) else {
          return None
        }
        cicp = true
      }
      b"sRGB" => {
        guard before_palette &&
          !srgb &&
          size == 1 &&
          bytes[offset + 8] <= b'\x03' &&
          png_chunk_crc_valid(bytes, offset, 1) else {
          return None
        }
        srgb = true
      }
      b"gAMA" => {
        guard before_palette &&
          !gamma &&
          size == 4 &&
          image_uint(bytes, offset + 8, 4) == 45455 &&
          png_chunk_crc_valid(bytes, offset, 4) else {
          return None
        }
        gamma = true
      }
      b"cHRM" => {
        guard before_palette &&
          !chromaticities &&
          size == 32 &&
          png_chunk_crc_valid(bytes, offset, 32) else {
          return None
        }
        // PNG Table 17 defines the compatibility values for an explicit sRGB chunk.
        for
          i, value in [
            31270L, 32900L, 64000L, 33000L, 30000L, 60000L, 15000L, 6000L,
          ] {
          guard image_uint(bytes, offset + 8 + i * 4, 4) == value else {
            return None
          }
        }
        chromaticities = true
      }
      b"IEND" => if offset + 12 != bytes.length() { return None }
      _ => return None
    }
    continue offset + 12 + size.to_int()
  }
  guard srgb || cicp || !(gamma || chromaticities) else { return None }
  let decoded = @raster.decode_png(bytes).to_rgba8() catch { _ => return None }
  let pixels = decoded.data
  let mut normalize = false
  for alpha = 3; alpha < pixels.length(); alpha = alpha + 4 {
    match pixels[alpha] {
      b'\xff' => ()
      b'\x00' =>
        if pixels[alpha - 3] != b'\x00' ||
          pixels[alpha - 2] != b'\x00' ||
          pixels[alpha - 1] != b'\x00' {
          normalize = true
        }
      _ => normalize = true
    }
  }
  let mut ambiguous = false
  let pixels = if normalize {
    Bytes::makei(pixels.length(), i => {
      if ambiguous || i % 4 == 3 {
        return pixels[i]
      }
      let alpha = pixels[i / 4 * 4 + 3].to_int()
      if alpha == 255 {
        pixels[i]
      } else if alpha == 0 {
        b'\x00'
      } else {
        let premultiplied = (pixels[i].to_int() * alpha + 127) / 255
        let numerator = premultiplied * 255
        // shortcut: defer half-way readback ties until Chromium's rounding is portable.
        if numerator % alpha * 2 == alpha {
          ambiguous = true
        }
        ((numerator + alpha / 2) / alpha).to_byte()
      }
    })
  } else {
    pixels
  }
  if ambiguous {
    None
  } else {
    Some(orient_raster(width, height, pixels, exif.unwrap_or(1)))
  }
}
