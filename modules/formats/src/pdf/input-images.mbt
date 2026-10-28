///|
fn image_size(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
) -> (Int32, Int32) raise @failure.Failure {
  let width = integer(get(document, object, "Width"))
  let height = integer(get(document, object, "Height"))
  guard width > 0 &&
    height > 0 &&
    width <= 4096 &&
    height <= 4096 &&
    width.to_int64() * height.to_int64() * 4 <= 16777216 else {
    @failure.reject("limit-exceeded", "PDF image dimensions exceed budget")
  }
  guard integer(get(document, object, "BitsPerComponent")) == 8 &&
    raw(object, "ImageMask") != @syntax.PdfBoolean(true) else {
    @failure.reject("unsupported-pdf", "PDF image requires 8-bit samples")
  }
  (width, height)
}

///|
fn image_decode(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
  channels : Int32,
) -> Array[Double] raise @failure.Failure {
  let value = get(document, object, "Decode")
  if value == @syntax.PdfNull {
    return Array::makei(channels * 2, i => if i % 2 == 0 { 0.0 } else { 1.0 })
  }
  guard value is PdfArray(items) && items.length() == channels * 2 else {
    @failure.reject("invalid-pdf", "Invalid image Decode array")
  }
  items.map(item => {
    let value = number(item)
    guard value >= 0 && value <= 1 else {
      @failure.reject("unsupported-pdf", "Unsupported image Decode range")
    }
    value
  })
}

///|
fn decoded_sample(value : Byte, low : Double, high : Double) -> Byte {
  ((low + (high - low) * value.to_int().to_double() / 255) * 255)
  .round()
  .to_int()
  .max(0)
  .min(255)
  .to_byte()
}

///|
fn check_jpeg(
  bytes : Bytes,
  width : Int32,
  height : Int32,
  channels : Int32,
) -> Unit raise {
  guard bytes.length() >= 4 && bytes[0:2] == b"\xff\xd8" else {
    @failure.reject("invalid-image", "DCT image is not a JPEG")
  }
  let mut index = 2
  let mut found = false
  while index < bytes.length() {
    @pdfcore.sdk_check(1)
    guard bytes[index] == 255 else {
      @failure.reject("invalid-image", "Malformed JPEG marker")
    }
    while index < bytes.length() && bytes[index] == 255 {
      @pdfcore.sdk_check(1)
      index += 1
    }
    guard index < bytes.length() else {
      @failure.reject("invalid-image", "Truncated JPEG marker")
    }
    let marker = bytes[index].to_int()
    index += 1
    if marker == 0xda {
      guard found else {
        @failure.reject("invalid-image", "JPEG has no frame header")
      }
      return
    }
    guard marker != 0xd9 && index + 2 <= bytes.length() else {
      @failure.reject("invalid-image", "Truncated JPEG header")
    }
    let length = bytes[index].to_int() * 256 + bytes[index + 1].to_int()
    guard length >= 2 && length <= bytes.length() - index else {
      @failure.reject("invalid-image", "Invalid JPEG marker length")
    }
    if marker == 0xe2 &&
      length >= 14 &&
      bytes[index + 2:index + 14] == b"ICC_PROFILE\x00" {
      @failure.reject("unsupported-pdf", "JPEG ICC profiles are unsupported")
    }
    if marker >= 0xc0 && marker <= 0xcf && ![0xc4, 0xc8, 0xcc].contains(marker) {
      guard [0xc0, 0xc1, 0xc2].contains(marker) &&
        length >= 8 &&
        bytes[index + 2] == 8 &&
        bytes[index + 3].to_int() * 256 + bytes[index + 4].to_int() == height &&
        bytes[index + 5].to_int() * 256 + bytes[index + 6].to_int() == width &&
        bytes[index + 7].to_int() == channels else {
        @failure.reject(
          "unsupported-pdf", "JPEG precision, color components, or dimensions do not match PDF",
        )
      }
      found = true
    }
    index += length
  }
  @failure.reject("invalid-image", "JPEG has no image scan")
}

///|
fn image_mask(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
  width : Int32,
  height : Int32,
) -> Bytes? raise {
  guard raw(object, "Mask") == @syntax.PdfNull else {
    @failure.reject(
      "unsupported-pdf", "Color-key and explicit image masks are unsupported",
    )
  }
  let mask = get(document, object, "SMask")
  if mask == @syntax.PdfNull {
    return None
  }
  guard image_size(document, mask) == (width, height) &&
    is_name(get(document, mask, "ColorSpace"), "DeviceGray") &&
    raw(mask, "SMask") == @syntax.PdfNull &&
    raw(mask, "Matte") == @syntax.PdfNull else {
    @failure.reject("unsupported-pdf", "Unsupported PDF soft mask")
  }
  let bytes = stream_bytes(document, mask)
  guard bytes.length() == width * height else {
    @failure.reject(
      "invalid-pdf", "PDF mask byte count does not match dimensions",
    )
  }
  let decode = image_decode(document, mask, 1)
  Some(
    Bytes::makei(bytes.length(), i => {
      decoded_sample(bytes[i], decode[0], decode[1])
    }),
  )
}

///|
fn add_image(
  context : ContentContext,
  object : @syntax.PdfObject,
  key : String,
) -> Unit raise {
  if context.imageKeys.contains(key) {
    return
  }
  guard context.imageKeys.length() < 256 else {
    @failure.reject("limit-exceeded", "PDF image count exceeds budget")
  }
  let document = context.session.document
  guard raw(object, "OC") == @syntax.PdfNull else {
    @failure.reject(
      "unsupported-pdf", "Optional PDF image content is unsupported",
    )
  }
  let (width, height) = image_size(document, object)
  let space = get(document, object, "ColorSpace")
  let gray = is_name(space, "DeviceGray")
  guard gray || is_name(space, "DeviceRGB") else {
    @failure.reject("unsupported-pdf", "PDF image color space is unsupported")
  }
  let channels = if gray { 1 } else { 3 }
  let decode = image_decode(document, object, channels)
  let alpha = image_mask(document, object, width, height)
  let filter = get(document, object, "Filter")
  if is_name(filter, "DCTDecode") ||
    (filter is PdfArray([PdfNameObject(name)]) && name == pdf_name("DCTDecode")) {
    guard raw(object, "DecodeParms") == @syntax.PdfNull else {
      @failure.reject("unsupported-pdf", "JPEG DecodeParms are unsupported")
    }
    let bytes = object.deep_copy().stream_bytes()
    check_jpeg(bytes, width, height, channels)
    @pdfcore.sdk_decoded(bytes.length())
    context.jpeg[key] = { bytes, width, height, decode, alpha, }
  } else {
    let bytes = stream_bytes(document, object)
    guard bytes.length() == width * height * channels else {
      @failure.reject(
        "invalid-pdf", "PDF image sample count does not match dimensions",
      )
    }
    @pdfcore.sdk_decoded(width * height * 4)
    let rgba = Bytes::makei(width * height * 4, i => {
      let pixel = i / 4
      let channel = i % 4
      if channel == 3 {
        alpha.map(mask => mask[pixel]).unwrap_or(255)
      } else {
        let source_channel = if gray { 0 } else { channel }
        decoded_sample(
          bytes[pixel * channels + source_channel],
          decode[source_channel * 2],
          decode[source_channel * 2 + 1],
        )
      }
    })
    context.images.add(key, width, height, rgba)
  }
  context.imageKeys.push(key)
}
