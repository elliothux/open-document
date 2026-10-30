///|
fn ContentContext::extracted_glyph(
  self : ContentContext,
  state : GraphicsState,
  font : SourceFont,
  text : @pdflite.PdfContentTextState,
  encoded : String?,
  quad : Array[Double],
  transform : @layout.Matrix,
  px : Double,
  py : Double,
  depth : Int32,
  group : Int32,
) -> Int32? raise @failure.Failure {
  guard self.extraction is Some(data) else { return None }
  guard data.glyphs.length() < 262144 else {
    @failure.reject(
      "limit-exceeded", "PDF extracted glyph count exceeds budget",
    )
  }
  let invisible = text.rendering_mode == 3 ||
    text.font_size == 0 ||
    state.style.fillAlpha == 0
  let clipped = self.extraction_clipped(quad)
  let (x, y) = transform.point(px, -py)
  let reason = if encoded is None {
    "Source Unicode mapping is unknown"
  } else if invisible {
    "Invisible source text is not emitted as visible content"
  } else if font.substituted {
    "Source font was substituted"
  } else if font.index is None {
    "Source font cannot be reconstructed"
  } else {
    extraction_style_reason(state.style, text=true)
  }
  let basis = state.matrix.then(matrix(text.text_matrix))
  let index = data.glyphs.length()
  let family = if font.index is Some(index) {
    data.families.get_or_init(index, () => {
      let family = self.probe.font_family(index) catch { _ => "" }
      if family.is_empty() {
        font.family
      } else {
        family
      }
    })
  } else {
    font.family
  }
  data.glyphOrigins.push((px, -py))
  data.glyphs.push({
    text: encoded.unwrap_or("\u{fffc}"),
    encodedText: encoded.unwrap_or(""),
    font: family,
    color: state.fill,
    fontIndex: font.index.unwrap_or(-1),
    glyph: 0U,
    size: text.font_size.abs() * (basis.c * basis.c + basis.d * basis.d).sqrt(),
    baseline: [x, y],
    quad: quad.copy(),
    inkQuad: [],
    transform: transform.then({ a: 1, b: 0, c: 0, d: -1, e: 0, f: 0, }),
    primitive: -1,
    group,
    mapped: encoded is Some(_),
    invisible,
    substituted: font.substituted,
    marked: !self.marked.is_empty(),
    clipped,
    formDepth: depth,
    annotation: !self.collectSource,
    cleanReason: reason,
  })
  Some(index)
}

///|
fn ContentContext::extracted_glyph_draw(
  self : ContentContext,
  index : Int32?,
  gid : UInt32,
) -> Unit raise @failure.Failure {
  if self.extraction is Some(data) && index is Some(index) {
    let item = data.glyphs[index]
    // Retain the original local origin to avoid a second matrix inversion.
    let (x, y) = data.glyphOrigins[index]
    let ink = glyph_ink_quad(
      self.probe,
      item.fontIndex,
      gid,
      item.transform,
      x,
      y,
    )
    let invisible = item.invisible ||
      (
        ink.is_empty() &&
        !item.encodedText.is_empty() &&
        !item.encodedText.iter().all(c => c.is_whitespace())
      )
    let clipped = self.extraction_clipped(
      if ink.is_empty() {
        item.baseline
      } else {
        ink
      },
    )
    data.glyphs[index] = {
      ..item,
      glyph: gid,
      inkQuad: ink,
      clipped,
      invisible,
      cleanReason: if !item.cleanReason.is_empty() {
        item.cleanReason
      } else if invisible {
        "Encoded source text has no visible glyph ink"
      } else if clipped {
        "Source glyph ink is clipped"
      } else {
        ""
      },
    }
    data.glyphCommands[self.commands.length()] = index
  }
}

///|
fn ContentContext::extracted_mark(
  self : ContentContext,
  start : Int32,
  replacement : String,
) -> Unit {
  if self.extraction is Some(data) && start < data.glyphs.length() {
    let original = data.glyphs[start:].map(glyph => glyph.encodedText).join("")
    for index in start..<data.glyphs.length() {
      let glyph = data.glyphs[index]
      data.glyphs[index] = {
        ..glyph,
        group: start,
        marked: true,
        text: if index == start {
          replacement
        } else {
          ""
        },
        cleanReason: if !glyph.cleanReason.is_empty() {
          glyph.cleanReason
        } else if original != replacement {
          "ActualText differs from the encoded glyph text"
        } else {
          ""
        },
      }
    }
  }
}

///|
fn ContentContext::extracted_path(
  self : ContentContext,
  path : Array[@layout.PathSegment],
  state : GraphicsState,
  fill : String,
  stroke : String,
  style : @layout.DrawStyle,
  depth : Int32,
) -> Unit raise @failure.Failure {
  if self.extraction is Some(data) {
    guard data.paths.length() < 65536 else {
      @failure.reject(
        "limit-exceeded", "PDF extracted path count exceeds budget",
      )
    }
    data.pathCommands[self.commands.length()] = data.paths.length()
    let points : Array[Double] = []
    for segment in path {
      match segment {
        Move(x, y) | Line(x, y) => points.append([x, y])
        Cubic(a, b, c, d, e, f) => points.append([a, b, c, d, e, f])
        Close => ()
      }
    }
    let width = state.width * extraction_scale(state.matrix)
    let clipped = self.extraction_clipped(
      points,
      margin=if stroke.is_empty() { 0 } else { width / 2 },
    )
    data.paths.push({
      path: path.copy(),
      fill,
      stroke,
      width,
      style,
      primitive: -1,
      clipped,
      formDepth: depth,
      annotation: !self.collectSource,
      cleanReason: if clipped {
        "Source path is explicitly clipped"
      } else if !stroke.is_empty() && state.width == 0 {
        "Device hairline strokes require an explicit output resolution"
      } else {
        extraction_style_reason(style)
      },
    })
  }
}

///|
fn ContentContext::extracted_image(
  self : ContentContext,
  reference : @syntax.PdfObject,
  key : String,
  state : GraphicsState,
  depth : Int32,
) -> Unit raise @failure.Failure {
  if self.extraction is Some(data) {
    guard data.images.length() < 4096 else {
      @failure.reject(
        "limit-exceeded", "PDF extracted image count exceeds budget",
      )
    }
    let transform = state.matrix.then({ a: 1, b: 0, c: 0, d: -1, e: 0, f: 1, })
    let (width, height, rgba, jpeg) = if self.jpeg.get(key) is Some(image) {
      (image.width, image.height, b"", Some(image.bytes))
    } else {
      let image = self.images.get(key)
      (image.width, image.height, image.rgba, None)
    }
    data.imageCommands[self.commands.length()] = data.images.length()
    let quad = extraction_quad(transform)
    let clipped = self.extraction_clipped(quad)
    data.images.push({
      key,
      pixelWidth: width,
      pixelHeight: height,
      rgba,
      jpeg,
      opacity: state.style.fillAlpha,
      transform,
      quad,
      primitive: -1,
      reference: match reference {
        PdfIndirect(number) => number
        _ => -1
      },
      formDepth: depth,
      clipped,
      simpleForm: data.formScopes.all(simple => simple),
      annotation: !self.collectSource,
      cleanReason: if clipped {
        "Source image is explicitly clipped"
      } else if state.style.multiply {
        "Source image blend mode requires explicit reconstruction"
      } else {
        ""
      },
    })
  }
}
