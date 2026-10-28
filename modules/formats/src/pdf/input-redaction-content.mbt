///|
fn redaction_affected(
  page : String,
  kind : String,
  bounds : RedactionBounds,
) -> Json {
  {
    "page": page,
    "kind": kind,
    "x": bounds.x,
    "y": bounds.y,
    "width": bounds.width,
    "height": bounds.height,
  }
}

///|
fn redaction_union(a : RedactionBounds, b : RedactionBounds) -> RedactionBounds {
  let x = a.x.min(b.x)
  let y = a.y.min(b.y)
  {
    x,
    y,
    width: (a.x + a.width).max(b.x + b.width) - x,
    height: (a.y + a.height).max(b.y + b.height) - y,
  }
}

///|
fn redaction_glyph_bounds(
  glyph : PdfExtractedGlyph,
) -> RedactionBounds raise @failure.Failure {
  let metrics = redaction_bounds(glyph.quad)
  if glyph.inkQuad.is_empty() {
    metrics
  } else {
    redaction_union(metrics, redaction_bounds(glyph.inkQuad))
  }
}

///|
fn redaction_primitive(
  primitive : @layout.PositionedPrimitive,
  fonts : Map[Int32, Int32],
  images : Map[String, String],
) -> @layout.PositionedPrimitive raise @failure.Failure {
  match primitive {
    Text(text) =>
      @layout.Text({
        text: text.text,
        runs: text.runs.map(run => {
          ..run,
          glyphs: run.glyphs.map(glyph => {
            guard fonts.get(glyph.font) is Some(font) else {
              @failure.reject(
                "protected-content", "A surviving glyph has no clean font",
              )
            }
            { ..glyph, font, }
          }),
        }),
      })
    Image(image, opacity) => {
      guard images.get(image.key) is Some(key) else {
        @failure.reject(
          "protected-content", "A surviving image has no clean pixel resource",
        )
      }
      @layout.Image({ ..image, key, }, opacity)
    }
    _ => primitive
  }
}

///|
fn redaction_prune_scopes(
  source : Array[@layout.PositionedPrimitive],
) -> Array[@layout.PositionedPrimitive] raise @failure.Failure {
  fn scope(
    start : Int32,
    depth : Int32,
    nested : Bool,
  ) -> (Array[@layout.PositionedPrimitive], Bool, Int32) raise @failure.Failure {
    guard depth <= 32 else {
      @failure.reject("limit-exceeded", "Clean drawing scopes exceed budget")
    }
    let result : Array[@layout.PositionedPrimitive] = []
    let mut painted = false
    let mut index = start
    while index < source.length() {
      let primitive = source[index]
      match primitive {
        Transform(_) | Clip(_) | ClipPath(_, _) => {
          let (children, visible, next) = scope(index + 1, depth + 1, true)
          if visible {
            result.push(primitive)
            result.append(children)
            result.push(@layout.Restore)
            painted = true
          }
          index = next
        }
        Restore => {
          guard nested else {
            @failure.reject(
              "protected-content", "Clean drawing scopes are unbalanced",
            )
          }
          return (result, painted, index + 1)
        }
        _ => {
          result.push(primitive)
          painted = true
          index += 1
        }
      }
    }
    guard !nested else {
      @failure.reject(
        "protected-content", "Clean drawing scopes are unbalanced",
      )
    }
    (result, painted, index)
  }
  scope(0, 0, false).0
}

///|
fn redaction_image_pixels(
  image : PdfExtractedImage,
  regions : Array[PdfRedactionRegion],
) -> (Bytes, RedactionBounds?) raise {
  let width = image.pixelWidth
  let height = image.pixelHeight
  guard width > 0 &&
    height > 0 &&
    width <= 4096 &&
    height <= 4096 &&
    image.rgba.length().to_int64() == width.to_int64() * height.to_int64() * 4 else {
    @failure.reject(
      "protected-content", "Redaction requires verified decoded image pixels",
    )
  }
  let mask : FixedArray[Bool] = FixedArray::make(width * height, false)
  let inverse = image.transform.inverse()
  let mut actual : RedactionBounds? = None
  for region in regions {
    let points : Array[Double] = []
    for
      (x, y) in [
        (region.x, region.y),
        (region.x + region.width, region.y),
        (region.x + region.width, region.y + region.height),
        (region.x, region.y + region.height),
      ] {
      let (u, v) = inverse.point(x, y)
      points.append([u, v])
    }
    let projected = redaction_bounds(points)
    // Padding is only for image samples near an intersecting region. Clamping
    // a disjoint region first would incorrectly redact an unrelated edge pixel.
    if projected.x > 1 ||
      projected.y > 1 ||
      projected.x + projected.width < 0 ||
      projected.y + projected.height < 0 {
      continue
    }
    let x0 = ((projected.x.max(0).min(1) * width.to_double()).floor().to_int() -
      1)
      .max(0)
      .min(width)
    let y0 = ((projected.y.max(0).min(1) * height.to_double()).floor().to_int() -
      1)
      .max(0)
      .min(height)
    let x1 = (((projected.x + projected.width).max(0).min(1) * width.to_double())
      .ceil()
      .to_int() +
      1)
      .max(0)
      .min(width)
    let y1 = (((projected.y + projected.height).max(0).min(1) *
      height.to_double())
      .ceil()
      .to_int() +
      1)
      .max(0)
      .min(height)
    if x1 <= x0 || y1 <= y0 {
      continue
    }
    for y in y0..<y1 {
      for x in x0..<x1 {
        @pdfcore.sdk_check(1)
        mask[y * width + x] = true
      }
    }
    let points : Array[Double] = []
    for (x, y) in [(x0, y0), (x1, y0), (x1, y1), (x0, y1)] {
      let (a, b) = image.transform.point(
        x.to_double() / width.to_double(),
        y.to_double() / height.to_double(),
      )
      points.append([a, b])
    }
    let bounds = redaction_bounds(points)
    actual = Some(
      match actual {
        Some(before) => redaction_union(before, bounds)
        None => bounds
      },
    )
  }
  let pixels = Bytes::makei(image.rgba.length(), i => {
    if i % 4 == 0 {
      @pdfcore.sdk_check(1)
    }
    if mask[i / 4] {
      if i % 4 == 3 {
        b'\xff'
      } else {
        b'\x00'
      }
    } else if image.rgba[i / 4 * 4 + 3] == 0 {
      b'\x00'
    } else {
      image.rgba[i]
    }
  })
  (pixels, actual)
}
