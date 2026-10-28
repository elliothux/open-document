///|
fn stream_bytes(
  document : @pdflite.PdfDocument,
  value : @syntax.PdfObject,
) -> Bytes raise {
  let source = resolve(document, value)
  guard source is PdfStreamObject(_) else {
    @failure.reject("invalid-pdf", "PDF content requires a stream")
  }
  let filter = get(document, source, "Filter")
  guard filter == @syntax.PdfNull ||
    is_name(filter, "FlateDecode") ||
    is_name(filter, "Fl") ||
    (
      filter is PdfArray([PdfNameObject(name)]) &&
      (name == pdf_name("FlateDecode") || name == pdf_name("Fl"))
    ) else {
    @failure.reject("unsupported-pdf", "Unsupported PDF stream filter")
  }
  let parameters = get(document, source, "DecodeParms")
  let parameters = match parameters {
    PdfArray([single]) => resolve(document, single)
    _ => parameters
  }
  if parameters != @syntax.PdfNull {
    let predictor = get(document, parameters, "Predictor")
    if predictor != @syntax.PdfNull && integer(predictor) != 1 {
      let columns = get(document, parameters, "Columns")
      let colors = get(document, parameters, "Colors")
      let bits = get(document, parameters, "BitsPerComponent")
      let columns = if columns == @syntax.PdfNull {
        1
      } else {
        integer(columns)
      }
      let colors = if colors == @syntax.PdfNull { 1 } else { integer(colors) }
      let bits = if bits == @syntax.PdfNull { 8 } else { integer(bits) }
      guard columns > 0 &&
        columns <= 4096 &&
        colors > 0 &&
        colors <= 4 &&
        [1, 2, 4, 8, 16].contains(bits) else {
        @failure.reject(
          "limit-exceeded", "PDF predictor geometry exceeds budget",
        )
      }
    }
  }
  let copied = source.deep_copy()
  if filter == @syntax.PdfNull {
    let bytes = copied.stream_bytes()
    @pdfcore.sdk_decoded(bytes.length())
    bytes
  } else {
    document.pdf_decode_stream(copied).stream_bytes()
  }
}

///|
fn content_bytes(
  document : @pdflite.PdfDocument,
  value : @syntax.PdfObject,
) -> Bytes raise {
  match resolve(document, value) {
    PdfNull => b""
    PdfArray(items) => {
      let output : Array[Byte] = []
      for item in items {
        let bytes = stream_bytes(document, item)
        guard bytes.length() < 16777216 - output.length() else {
          @failure.reject("limit-exceeded", "PDF page content exceeds budget")
        }
        for byte in bytes {
          output.push(byte)
        }
        output.push(10)
      }
      Bytes::from_array(output)
    }
    _ => stream_bytes(document, value)
  }
}

///|
priv struct SourceFont {
  family : String
  font : @pdflite.PdfFont
  index : Int32?
  gidMap : Bytes?
  cid : Bool
  substituted : Bool
  symbolic : Bool
  unicodeMap : Map[Int32, String?]
  glyphs : Map[Int32, (String, Int32, UInt32)?]
}

///|
fn font_resource(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  name : @pdfcore.PdfName,
  probe : @layout.TextProbe,
  supplied : @layout.TextProbe,
  profile : Map[String, String],
  diagnostics : Array[String],
) -> SourceFont raise {
  let fonts = get(document, resources, "Font")
  let object = get(
    document,
    fonts,
    @utf8.decode_lossy(name.bytes())[1:].to_owned(),
  )
  guard object != @syntax.PdfNull else {
    @failure.reject("invalid-pdf", "Missing PDF font resource")
  }
  if is_name(get(document, object, "Subtype"), "Type0") &&
    !is_name(get(document, object, "Encoding"), "Identity-H") {
    @failure.reject(
      "unsupported-pdf", "Only Identity-H composite font encoding is supported",
    )
  }
  // Validate font streams before the dependency's font parser consumes them.
  for
    target in [object] +
    (match get(document, object, "DescendantFonts") {
      PdfArray(items) => items
      _ => []
    }) {
    let descriptor = get(document, target, "FontDescriptor")
    for key in ["FontFile", "FontFile2", "FontFile3"] {
      let stream = raw(descriptor, key)
      if stream != @syntax.PdfNull {
        ignore(stream_bytes(document, stream))
      }
    }
    let unicode = raw(target, "ToUnicode")
    if unicode != @syntax.PdfNull {
      ignore(stream_bytes(document, unicode))
    }
  }
  let unicode = raw(object, "ToUnicode")
  if unicode != @syntax.PdfNull {
    ignore(stream_bytes(document, unicode))
  }
  let font = document.read_font(object)
  let cid = font is PdfFontCIDKeyed(_)
  let mut supported = is_name(get(document, object, "Subtype"), "TrueType")
  let mut gid_map : Bytes? = None
  if cid {
    supported = font.is_identity_h()
    guard get(document, object, "DescendantFonts") is PdfArray([descendant]) else {
      @failure.reject("unsupported-pdf", "PDF requires one descendant font")
    }
    let descendant = resolve(document, descendant)
    supported = supported &&
      is_name(get(document, descendant, "Subtype"), "CIDFontType2")
    let mapping = get(document, descendant, "CIDToGIDMap")
    if mapping != @syntax.PdfNull && !is_name(mapping, "Identity") {
      gid_map = Some(stream_bytes(document, mapping))
      guard gid_map.unwrap().length() % 2 == 0 else {
        @failure.reject("invalid-pdf", "Invalid CIDToGIDMap length")
      }
    }
  }
  let base = get(document, object, "BaseFont")
  let base = if base is PdfNameObject(name) {
    @utf8.decode_lossy(name.bytes())[1:].to_owned()
  } else {
    ""
  }
  let mut substituted = false
  let flags = get(document, get(document, object, "FontDescriptor"), "Flags")
  let symbolic = !cid &&
    raw(object, "Encoding") == @syntax.PdfNull &&
    flags != @syntax.PdfNull &&
    (integer(flags) & 4) != 0
  let index = if supported && font.embedded_fontfile_number() is Some(id) {
    let identity = "pdf-font-\{id}"
    Some(
      if probe.font_info().any(font => font.identity == identity) {
        probe.font_index(identity)
      } else {
        probe.add_source_font(
          stream_bytes(document, @syntax.PdfIndirect(id)),
          identity,
        )
      },
    )
  } else if @layout.font_profile_identity(profile, base) is Some(identity) {
    substituted = true
    diagnostics.push("Explicit font substitution: " + base)
    let key = "pdf-substitute-" + base
    Some(
      if probe.font_info().any(font => font.identity == key) {
        probe.font_index(key)
      } else {
        probe.add_font(supplied.font_bytes(supplied.font_index(identity)), key)
      },
    )
  } else {
    diagnostics.push(
      "Font cannot be displayed without a supported embedded or explicit substitute font: " +
      base,
    )
    None
  }
  {
    family: base,
    font,
    index,
    gidMap: gid_map,
    cid,
    substituted,
    symbolic,
    unicodeMap: Map([]),
    glyphs: Map([]),
  }
}

///|
fn SourceFont::unicode(self : SourceFont, code : Int32) -> String? {
  match self.unicodeMap.get(code) {
    Some(value) => value
    None => {
      let value = source_unicode(self.font, code)
      self.unicodeMap[code] = value
      value
    }
  }
}

///|
fn source_unicode(font : @pdflite.PdfFont, code : Int32) -> String? {
  guard font.sdk_unicode(code) is Some(points) && !points.is_empty() else {
    return None
  }
  let text = StringBuilder()
  for value in points {
    guard value >= 0 &&
      value <= 0x10ffff &&
      !(value >= 0xd800 && value <= 0xdfff) else {
      return None
    }
    text.write_char(value.to_char().unwrap())
  }
  Some(text.to_string())
}

///|
fn encoded_font(font : @pdflite.PdfFont) -> @pdflite.PdfFont {
  match font {
    PdfFontSimple(simple) =>
      @pdflite.PdfFontSimple({
        ..simple,
        fontdescriptor: simple.fontdescriptor.map(d => { ..d, tounicode: None, }),
      })
    _ => font
  }
}

///|
fn pdf_text_string(object : @syntax.PdfObject) -> String raise @failure.Failure {
  guard object is PdfString(bytes) else {
    @failure.reject("invalid-pdf", "PDF text string is required")
  }
  if bytes.length() >= 2 && bytes[0:2] == b"\xfe\xff" {
    @utf16.decode(bytes[2:], endianness=Big) catch {
      _ => @failure.reject("invalid-pdf", "Malformed PDF UTF-16 string")
    }
  } else {
    @utf8.decode_lossy(
      @pdflite.pdf_utf8_of_pdfdocstring(bytes) catch {
        _ => @failure.reject("invalid-pdf", "Malformed PDFDocEncoding string")
      },
    )
  }
}
