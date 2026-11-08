///|
fn embedded_cff(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
  cid : Bool,
) -> @pdflite.SdkCffFont? raise {
  let target = if cid {
    guard get(document, object, "DescendantFonts") is PdfArray([target]) else {
      @failure.reject("invalid-pdf", "PDF requires one descendant font")
    }
    resolve(document, target)
  } else {
    object
  }
  let subtype = get(document, target, "Subtype")
  if !(if cid {
      is_name(subtype, "CIDFontType0")
    } else {
      is_name(subtype, "Type1") || is_name(subtype, "MMType1")
    }) {
    return None
  }
  let descriptor = get(document, target, "FontDescriptor")
  let stream = get(document, descriptor, "FontFile3")
  if stream == @syntax.PdfNull {
    return None
  }
  let stream_subtype = get(document, stream, "Subtype")
  if !is_name(stream_subtype, "OpenType") &&
    !is_name(stream_subtype, if cid { "CIDFontType0C" } else { "Type1C" }) {
    return None
  }
  Some(
    @pdflite.SdkCffFont::new(
      stream_bytes(document, stream),
      cid,
      !cid && raw(object, "Encoding") == @syntax.PdfNull,
    ),
  )
}

///|
fn draw_font_outline(
  context : ContentContext,
  identity : String,
  outline : Array[@pdflite.SdkCffSegment],
  width : Double,
  transform : @layout.Matrix,
  state : GraphicsState,
  value : String,
) -> Unit raise {
  @pdfcore.sdk_decoded(32)
  let cached = context.nativeOutlines.get(identity)
  let path = StringBuilder()
  let ink : Array[Double] = []
  fn point(x : Double, y : Double) -> Unit raise @failure.Failure {
    let (x, y) = checked_point(transform, x, y)
    if ink.is_empty() {
      ink.append([x, y, x, y])
    } else {
      ink[0] = ink[0].min(x)
      ink[1] = ink[1].min(y)
      ink[2] = ink[2].max(x)
      ink[3] = ink[3].max(y)
    }
  }
  for segment in outline {
    @pdfcore.sdk_check(1)
    match segment {
      CffMove(x, y) => {
        point(x, y)
        if cached is None {
          path <+ "M\{x} \{y}"
        }
      }
      CffLine(x, y) => {
        point(x, y)
        if cached is None {
          path <+ "L\{x} \{y}"
        }
      }
      CffCubic(a, b, c, d, x, y) => {
        point(a, b)
        point(c, d)
        point(x, y)
        if cached is None {
          path <+ "C\{a} \{b} \{c} \{d} \{x} \{y}"
        }
      }
      CffClose => if cached is None { path.write_char('Z') }
    }
  }
  if ink.is_empty() && value.iter().all(c => c.is_whitespace()) {
    point(0, 0)
    point(width, 0)
  }
  let index = context.spans.length() - 1
  context.spans[index] = {
    ..context.spans[index],
    cropVisible: crop_intersects(context.page, ink),
  }
  if !outline.is_empty() {
    let key = if cached is Some(outline) {
      outline.key
    } else {
      let path = path.to_string()
      guard path.length() <= 8388608 - context.nativeOutlineBytes.val else {
        @failure.reject(
          "limit-exceeded", "PDF native outline cache exceeds budget",
        )
      }
      @pdfcore.sdk_decoded(path.length() * 2)
      @pdfcore.sdk_check(path.length())
      let digest = StringBuilder()
      digest <+ "pdf-glyph:"
      for byte in @crypto.sha256(@utf8.encode(path)) {
        digest.write_string(byte.to_int().to_string(radix=16).pad_start(2, '0'))
      }
      let key = digest.to_string()
      context.nativeOutlineBytes.val += path.length()
      context.nativeOutlines[identity] = { key, path, }
      key
    }
    check_style(state.style, state.width)
    context.commands.push(@layout.Style(state.style))
    context.scope(@layout.Transform(transform))
    context.commands.push(
      @layout.Glyphs(0, 0, state.fill, [
        {
          outline: key,
          upem: 1,
          fontBounds: None,
          strokeWidth: 0,
          x: 0,
          y: 0,
          scaleX: 1,
          scaleY: 1,
        },
      ]),
    )
    context.restore()
  }
}
