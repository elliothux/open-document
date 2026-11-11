///|
fn image_size(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
) -> (Int32, Int32) raise @failure.Failure {
  let width = integer(get(document, object, "Width"))
  let height = integer(get(document, object, "Height"))
  guard width > 0 &&
    height > 0 &&
    width <= @layout.ImageDimension &&
    height <= @layout.ImageDimension &&
    width.to_int64() * height.to_int64() * 4 <= @layout.ImageBytes.to_int64() else {
    @failure.reject("limit-exceeded", "PDF image dimensions exceed budget")
  }
  guard (
      jpx_filter(document, object) ||
      [1, 8].contains(integer(get(document, object, "BitsPerComponent")))
    ) &&
    raw(object, "ImageMask") != @syntax.PdfBoolean(true) else {
    @failure.reject(
      "unsupported-pdf", "PDF image requires 1-bit or 8-bit samples",
    )
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
) -> (Int32?, Int32) raise {
  guard bytes.length() >= 4 && bytes[0:2] == b"\xff\xd8" else {
    @failure.reject("invalid-image", "DCT image is not a JPEG")
  }
  let mut index = 2
  let mut found = false
  let mut transform : Int32? = None
  let mut blocks = 0
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
      return (transform, blocks)
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
    if marker == 0xee && length >= 14 && bytes[index + 2:index + 7] == b"Adobe" {
      guard transform is None else {
        @failure.reject("invalid-image", "Duplicate Adobe JPEG transform")
      }
      transform = Some(bytes[index + 13].to_int())
    }
    if marker >= 0xc0 && marker <= 0xcf && ![0xc4, 0xc8, 0xcc].contains(marker) {
      guard [0xc0, 0xc1, 0xc2].contains(marker) &&
        !found &&
        length >= 8 + channels * 3 &&
        bytes[index + 2] == 8 &&
        bytes[index + 3].to_int() * 256 + bytes[index + 4].to_int() == height &&
        bytes[index + 5].to_int() * 256 + bytes[index + 6].to_int() == width &&
        bytes[index + 7].to_int() == channels else {
        @failure.reject(
          "unsupported-pdf", "JPEG precision, color components, or dimensions do not match PDF",
        )
      }
      let mut max_h = 1
      let mut max_v = 1
      let mut per_mcu = 0
      for channel in 0..<channels {
        let sample = bytes[index + 9 + channel * 3].to_int()
        let horizontal = sample >> 4
        let vertical = sample & 15
        guard horizontal >= 1 &&
          horizontal <= 4 &&
          vertical >= 1 &&
          vertical <= 4 else {
          @failure.reject("invalid-image", "Invalid JPEG sampling factors")
        }
        max_h = max_h.max(horizontal)
        max_v = max_v.max(vertical)
        per_mcu += horizontal * vertical
      }
      guard channels == 1 || per_mcu <= 10 else {
        @failure.reject("invalid-image", "JPEG MCU exceeds component budget")
      }
      blocks = if channels == 1 {
        (width + 7) / 8 * ((height + 7) / 8)
      } else {
        (width + max_h * 8 - 1) /
        (max_h * 8) *
        ((height + max_v * 8 - 1) / (max_v * 8)) *
        per_mcu
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
  if jpx_filter(document, mask) {
    return Some(jpx_mask(document, mask, width, height))
  }
  guard image_size(document, mask) == (width, height) &&
    integer(get(document, mask, "BitsPerComponent")) == 8 &&
    is_name(get(document, mask, "ColorSpace"), "DeviceGray") &&
    raw(mask, "SMask") == @syntax.PdfNull else {
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
fn image_matte(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
  channels : Int32,
) -> Array[Double]? raise @failure.Failure {
  let value = get(document, get(document, object, "SMask"), "Matte")
  matte_components(value, channels)
}

///|
fn matte_components(
  value : @syntax.PdfObject,
  channels : Int32,
) -> Array[Double]? raise @failure.Failure {
  if value == @syntax.PdfNull {
    return None
  }
  guard value is PdfArray(values) && values.length() == channels else {
    @failure.reject(
      "invalid-pdf", "PDF Matte must match the image color components",
    )
  }
  Some(
    values.map(value => {
      let component = number(value)
      guard component >= 0 && component <= 1 else {
        @failure.reject(
          "invalid-pdf", "PDF Matte component leaves the color range",
        )
      }
      component
    }),
  )
}

///|
fn unblend_sample(value : Byte, alpha : Byte, matte : Double) -> Byte {
  if alpha == 0 {
    return 0
  }
  let opacity = alpha.to_int().to_double() / 255
  ((value.to_int().to_double() - matte * 255 * (1 - opacity)) / opacity)
  .round()
  .to_int()
  .max(0)
  .min(255)
  .to_byte()
}

///|
fn add_image(
  context : ContentContext,
  object : @syntax.PdfObject,
  key : String,
  resources : @syntax.PdfObject,
) -> Unit raise {
  if context.imageKeys.contains(key) {
    return
  }
  guard context.imageKeys.length() < 256 else {
    @failure.reject("limit-exceeded", "PDF image count exceeds budget")
  }
  let document = context.session.document
  let (width, height) = image_size(document, object)
  if jpx_filter(document, object) {
    add_jpx_image(context, object, key, resources, width, height)
    context.imageKeys.push(key)
    return
  }
  let space = context.color_space(
    resources,
    get(document, object, "ColorSpace"),
  )
  let gray = space.components() == 1
  let cmyk = space is CmykColor
  guard gray || cmyk || space is (RgbColor | IccColor(_)) else {
    @failure.reject("unsupported-pdf", "PDF image color space is unsupported")
  }
  let profile = match space {
    IccColor(profile) if !profile.srgb => Some(profile)
    _ => None
  }
  let channels = space.components()
  let bits = integer(get(document, object, "BitsPerComponent"))
  let decode = image_decode(document, object, channels)
  let alpha = image_mask(document, object, width, height)
  let matte = image_matte(document, object, channels)
  @pdfcore.sdk_check(width * height)
  let filter = get(document, object, "Filter")
  if is_name(filter, "DCTDecode") ||
    (filter is PdfArray([PdfNameObject(name)]) && name == pdf_name("DCTDecode")) {
    guard bits == 8 else {
      @failure.reject("invalid-pdf", "JPEG requires 8-bit samples")
    }
    guard raw(object, "DecodeParms") == @syntax.PdfNull else {
      @failure.reject("unsupported-pdf", "JPEG DecodeParms are unsupported")
    }
    let bytes = object.deep_copy().stream_bytes()
    let (transform, blocks) = check_jpeg(bytes, width, height, channels)
    if cmyk {
      cmyk_pixels(
        context, key, bytes, width, height, transform, blocks, decode, alpha, matte,
      )
    } else {
      @pdfcore.sdk_decoded(bytes.length())
      context.jpeg[key] = {
        bytes,
        width,
        height,
        blocks,
        decode,
        alpha,
        matte,
        profile,
      }
    }
  } else {
    let bytes = image_stream_bytes(
      document, object, width, height, channels, bits,
    )
    let stride = (width * channels * bits + 7) / 8
    guard bytes.length() == stride * height else {
      @failure.reject(
        "invalid-pdf", "PDF image sample count does not match dimensions",
      )
    }
    @pdfcore.sdk_decoded(width * height * 4)
    if cmyk {
      let samples = if bits == 8 {
        bytes
      } else {
        @pdfcore.sdk_decoded(width * height * 4)
        Bytes::makei(width * height * 4, index => {
          let sample = index % (width * 4)
          let value = bytes[index / (width * 4) * stride + sample / 8].to_int()
          if ((value >> (7 - sample % 8)) & 1) == 0 {
            0
          } else {
            255
          }
        })
      }
      context.images.add(
        key,
        width,
        height,
        cmyk_rgba(samples, width * height, None, decode, alpha, matte),
      )
      context.imageKeys.push(key)
      return
    }
    let rgba = Bytes::makei(width * height * 4, i => {
      let pixel = i / 4
      let channel = i % 4
      if channel == 3 {
        alpha.map(mask => mask[pixel]).unwrap_or(255)
      } else {
        let source_channel = if gray { 0 } else { channel }
        let value = decoded_sample(
          if bits == 8 {
            bytes[pixel * channels + source_channel]
          } else {
            let sample = pixel % width * channels + source_channel
            let value = bytes[pixel / width * stride + sample / 8].to_int()
            if ((value >> (7 - sample % 8)) & 1) == 0 {
              0
            } else {
              255
            }
          },
          decode[source_channel * 2],
          decode[source_channel * 2 + 1],
        )
        if matte is Some(matte) && alpha is Some(alpha) {
          unblend_sample(value, alpha[pixel], matte[source_channel])
        } else {
          value
        }
      }
    })
    context.images.add(key, width, height, icc_rgba(rgba, profile))
  }
  context.imageKeys.push(key)
}

///|
fn icc_rgba(rgba : Bytes, profile : IccProfile?) -> Bytes raise {
  guard profile is Some(profile) else { return rgba }
  @pdfcore.sdk_check(rgba.length() / 4)
  @pdfcore.sdk_decoded(rgba.length())
  let channels = profile.curves.length()
  let mut color = [0.0, 0.0, 0.0]
  let cache : Map[Int32, Array[Double]] = Map([])
  Bytes::makei(rgba.length(), i => {
    let channel = i % 4
    if channel == 3 {
      return rgba[i]
    }
    if channel == 0 {
      let key = if channels == 1 {
        rgba[i].to_int()
      } else {
        (rgba[i].to_int() << 16) |
        (rgba[i + 1].to_int() << 8) |
        rgba[i + 2].to_int()
      }
      color = match cache.get(key) {
        Some(value) => value
        None => {
          @pdfcore.sdk_check(96)
          let value = profile.rgb(
            Array::makei(channels, c => rgba[i + c].to_int().to_double() / 255),
          )
          if cache.length() < 256 {
            @pdfcore.sdk_decoded(32)
            cache[key] = value
          }
          value
        }
      }
    }
    (color[channel] * 255).round().to_int().max(0).min(255).to_byte()
  })
}
