///|
fn jpx_filter(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
) -> Bool raise @failure.Failure {
  let filter = get(document, object, "Filter")
  is_name(filter, "JPXDecode") ||
  (filter is PdfArray([PdfNameObject(name)]) && name == pdf_name("JPXDecode"))
}

///|
fn jpx_image(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
  width : Int32,
  height : Int32,
) -> JpxPixels raise {
  guard get(document, object, "DecodeParms") == @syntax.PdfNull else {
    @failure.reject("unsupported-pdf", "JPEG2000 DecodeParms are unsupported")
  }
  let decoded = jpx_decode(
    object.deep_copy().stream_bytes(),
    expected=Some((width, height)),
  )
  guard decoded.width == width && decoded.height == height else {
    @failure.reject(
      "invalid-pdf", "JPEG2000 dimensions do not match the PDF image",
    )
  }
  decoded
}

///|
fn jpx_mask(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
  width : Int32,
  height : Int32,
) -> Bytes raise {
  guard image_size(document, object) == (width, height) &&
    raw(object, "SMask") == @syntax.PdfNull &&
    raw(object, "Mask") == @syntax.PdfNull else {
    @failure.reject("unsupported-pdf", "Unsupported JPEG2000 soft mask")
  }
  let decoded = jpx_image(document, object, width, height)
  let space = get(document, object, "ColorSpace")
  guard decoded.components.length() == 1 &&
    decoded.alpha is None &&
    (
      is_name(space, "DeviceGray") ||
      (space == @syntax.PdfNull && decoded.color == Some(17))
    ) else {
    @failure.reject(
      "unsupported-pdf", "JPEG2000 soft masks require grayscale samples",
    )
  }
  // JPX supplies precision and normalized samples; the PDF Decode entry is ignored.
  decoded.samples
}

///|
fn add_jpx_image(
  context : ContentContext,
  object : @syntax.PdfObject,
  key : String,
  resources : @syntax.PdfObject,
  width : Int32,
  height : Int32,
) -> Unit raise {
  let document = context.session.document
  let decoded = jpx_image(document, object, width, height)
  let mode = get(document, object, "SMaskInData")
  let mode = if mode == @syntax.PdfNull { 0 } else { integer(mode) }
  guard mode >= 0 && mode <= 2 else {
    @failure.reject("invalid-pdf", "Invalid JPEG2000 opacity mode")
  }
  let total = decoded.components.length()
  let alpha_index = match decoded.alpha {
    Some(index) => Some(index)
    None => if mode > 0 { Some(total - 1) } else { None }
  }
  let source = get(document, object, "ColorSpace")
  let ycc = source == @syntax.PdfNull && decoded.color == Some(18)
  let inferred = match decoded.color {
    Some(16 | 18) => "DeviceRGB"
    Some(17) => "DeviceGray"
    _ =>
      match total - (if alpha_index is Some(_) { 1 } else { 0 }) {
        1 => "DeviceGray"
        3 => "DeviceRGB"
        4 => "DeviceCMYK"
        _ =>
          @failure.reject(
            "unsupported-pdf", "JPEG2000 image has no supported color space",
          )
      }
  }
  let space = context.color_space(
    resources,
    if source == @syntax.PdfNull {
      tag(inferred)
    } else {
      source
    },
  )
  guard space is (GrayColor | RgbColor | CmykColor | IccColor(_)) else {
    @failure.reject("unsupported-pdf", "Unsupported JPEG2000 image color space")
  }
  let channels = space.components()
  guard channels + (if alpha_index is Some(_) { 1 } else { 0 }) == total &&
    (!ycc || channels == 3) else {
    @failure.reject(
      "invalid-pdf", "JPEG2000 components do not match the PDF color space",
    )
  }
  guard mode == 0 || raw(object, "SMask") == @syntax.PdfNull else {
    @failure.reject(
      "invalid-pdf", "JPEG2000 embedded alpha conflicts with SMask",
    )
  }
  let external = image_mask(document, object, width, height)
  let alpha = if mode > 0 {
    let index = alpha_index.unwrap()
    @pdfcore.sdk_decoded(width * height)
    Some(Bytes::makei(width * height, i => decoded.samples[i * total + index]))
  } else {
    external
  }
  let premultiplied = mode == 2 || (mode == 1 && decoded.associated)
  let matte = if premultiplied {
    matte_components(
      if mode == 2 {
        get(document, object, "Matte")
      } else {
        @syntax.PdfNull
      },
      channels,
    ).unwrap_or(Array::make(channels, 0.0))
    |> Some
  } else {
    image_matte(document, object, channels)
  }
  @pdfcore.sdk_decoded(width * height * channels)
  @pdfcore.sdk_check(width * height * channels)
  let samples = Bytes::makei(width * height * channels, i => {
    let pixel = i / channels
    let channel = i % channels
    let index = channel +
      (if alpha_index is Some(index) && channel >= index { 1 } else { 0 })
    let value = if ycc {
      let y = decoded.samples[pixel * total].to_int().to_double()
      let cb = decoded.samples[pixel * total + 1].to_int().to_double() - 128.0
      let cr = decoded.samples[pixel * total + 2].to_int().to_double() - 128.0
      (match channel {
        0 => y + 1.402 * cr
        1 => y - 0.344136 * cb - 0.714136 * cr
        _ => y + 1.772 * cb
      })
      .round()
      .to_int()
      .max(0)
      .min(255)
      .to_byte()
    } else {
      decoded.samples[pixel * total + index]
    }
    if matte is Some(matte) && alpha is Some(alpha) {
      unblend_sample(value, alpha[pixel], matte[channel])
    } else {
      value
    }
  })
  @pdfcore.sdk_decoded(width * height * 4)
  let rgba = if space is CmykColor {
    cmyk_rgba(
      samples,
      width * height,
      None,
      Array::makei(8, i => if i % 2 == 0 { 0.0 } else { 1.0 }),
      alpha,
      None,
    )
  } else {
    let rgba = Bytes::makei(width * height * 4, i => {
      let pixel = i / 4
      let channel = i % 4
      if channel == 3 {
        alpha.map(a => a[pixel]).unwrap_or(255)
      } else {
        samples[pixel * channels + (if channels == 1 { 0 } else { channel })]
      }
    })
    icc_rgba(
      rgba,
      match space {
        IccColor(profile) => Some(profile)
        _ => None
      },
    )
  }
  context.images.add(key, width, height, rgba)
}
