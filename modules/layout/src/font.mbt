///|
struct Font {
  font : @font.Font
  identity : String
  upem : Int32
  bytes : Bytes
  sha256 : String
  ascent : Int32
  descent : Int32
  line_gap : Int32
  fs_type : Int32
  bbox : Array[Int32]
  cap_height : Int32
  italic_angle : Double
}

///|
fn font_line_extents(
  face : @face.Face,
  os2 : @sfnt.Os2Table?,
) -> (Int32, Int32, Int32) raise @failure.Failure {
  let hhea = match face.reference_table(@common.Tag::from_string("hhea")) {
    Ok(blob) => blob.as_view()
    Err(_) => @failure.reject("malformed-font", "Missing hhea metrics")
  }
  guard hhea.length() >= 36 else {
    @failure.reject("malformed-font", "Invalid hhea metrics")
  }
  let signed = fn(offset) {
    let value = hhea[offset].to_int() * 256 + hhea[offset + 1].to_int()
    if value >= 32768 {
      value - 65536
    } else {
      value
    }
  }
  let ascent = signed(4)
  let descent = signed(6)
  // Win metrics bound clipping; USE_TYPO_METRICS overrides valid hhea line metrics.
  if os2 is Some(os2) {
    let table = face
      .reference_table(@common.Tag::from_string("OS/2"))
      .unwrap()
      .as_view()
    if ((table[62].to_int() * 256 + table[63].to_int()) & 128) != 0 &&
      os2.typo_ascender >= 0 &&
      os2.typo_descender <= 0 &&
      os2.typo_ascender > os2.typo_descender {
      return (os2.typo_ascender, -os2.typo_descender, os2.typo_line_gap.max(0))
    }
  }
  if ascent >= 0 && descent <= 0 && ascent > descent {
    (ascent, -descent, signed(8).max(0))
  } else if os2 is Some(os2) {
    (os2.win_ascent, os2.win_descent, 0)
  } else {
    @failure.reject("malformed-font", "Source font has no valid line metrics")
  }
}

///|
pub struct TextProbe {
  fonts : Array[Font]
  outlines : Map[String, String]
  outline_boxes : Map[String, Array[Double]]
  mut font_bytes : Int32
  mut outline_bytes : Int32
  mut closed : Bool
  mut paragraphs : Map[String, Array[MeasuredLine]]
  mut text_units : Int32
  mut pagination : PaginationCache?
  mut measured_shape : MeasuredShape?
}

///|
pub fn TextProbe::new() -> TextProbe {
  {
    fonts: [],
    outlines: Map([]),
    outline_boxes: Map([]),
    font_bytes: 0,
    outline_bytes: 0,
    closed: false,
    paragraphs: Map([]),
    text_units: 0,
    pagination: None,
    measured_shape: None,
  }
}

///|
fn TextProbe::check(self : TextProbe) -> Unit raise @failure.Failure {
  guard !self.closed else {
    @failure.reject("closed-session", "Text probe is closed")
  }
}

///|
/// Fonts are tried in supplied order; face 0 and default variation coordinates only.
pub fn TextProbe::add_font(
  self : TextProbe,
  bytes : Bytes,
  identity : String,
) -> Int32 raise @failure.Failure {
  self.add_font_data(bytes, identity, true)
}

///|
/// Positioned glyph fonts may omit cmap and OS/2; their source mapping owns Unicode.
pub fn TextProbe::add_source_font(
  self : TextProbe,
  bytes : Bytes,
  identity : String,
) -> Int32 raise @failure.Failure {
  self.add_font_data(bytes, identity, false)
}

///|
fn TextProbe::add_font_data(
  self : TextProbe,
  bytes : Bytes,
  identity : String,
  unicode : Bool,
) -> Int32 raise @failure.Failure {
  self.check()
  self.measured_shape = None
  guard self.fonts.length() < 8 && bytes.length() <= 33554432 - self.font_bytes else {
    @failure.reject("limit-exceeded", "Font budget exceeded")
  }
  guard !identity.is_empty() &&
    identity.length() <= 256 &&
    !self.fonts.iter().any(f => f.identity == identity) else {
    @failure.reject(
      "invalid-operation", "Font identity must be unique and nonempty",
    )
  }
  guard bytes.length() >= 12 && bytes[0:4] == b"\x00\x01\x00\x00" else {
    @failure.reject(
      "unsupported-font", "Only standalone TrueType outlines are supported; CFF and collections are unsupported",
    )
  }
  let face = @face.Face::from_bytes(bytes)
  match face.ensure_sfnt_tables() {
    Err(_) => @failure.reject("malformed-font", "Invalid font directory")
    Ok(_) => ()
  }
  let font = @font.Font::new(face)
  let head = match face.reference_table(@common.Tag::from_string("head")) {
    Err(_) => @failure.reject("malformed-font", "Missing head table")
    Ok(blob) =>
      match @sfnt.HeadTable::parse(blob.as_view()) {
        Err(_) => @failure.reject("malformed-font", "Invalid head table")
        Ok(head) => head
      }
  }
  let upem = head.units_per_em
  guard upem >= 16 && upem <= 16384 else {
    @failure.reject("malformed-font", "Invalid font metrics")
  }
  if unicode {
    match font.glyph_for_codepoint(32U) {
      Err(_) => @failure.reject("malformed-font", "Invalid font cmap")
      Ok(_) => ()
    }
  }
  font.set_scale(upem, upem)
  let os2 = match font.os2() {
    Ok(Some(table)) => Some(table)
    Ok(None) if !unicode => None
    _ => @failure.reject("malformed-font", "Missing or invalid OS/2 metrics")
  }
  let digest = @crypto.sha256(bytes)
  let head_bytes = face
    .reference_table(@common.Tag::from_string("head"))
    .unwrap()
    .as_view()
  guard head_bytes.length() >= 54 &&
    (
      os2 is None ||
      (os2 is Some(table) && table.win_ascent + table.win_descent > 0)
    ) else {
    @failure.reject("malformed-font", "Invalid line or bounding metrics")
  }
  let (ascent, descent, line_gap) = font_line_extents(face, os2)
  let bbox = [36, 38, 40, 42].map(offset => {
    let value = head_bytes[offset].to_int() * 256 +
      head_bytes[offset + 1].to_int()
    if value >= 32768 {
      value - 65536
    } else {
      value
    }
  })
  let digits = "0123456789abcdef"
  let hash = StringBuilder()
  for byte in digest {
    hash.write_char(digits[byte.to_int() >> 4].to_char().unwrap())
    hash.write_char(digits[byte.to_int() & 15].to_char().unwrap())
  }
  self.fonts.push({
    font,
    identity,
    upem,
    bytes,
    sha256: hash.to_string(),
    ascent,
    descent,
    line_gap,
    fs_type: os2.map(table => table.fs_type).unwrap_or(2),
    bbox,
    cap_height: os2
    .map(table => table.cap_height.unwrap_or(table.win_ascent))
    .unwrap_or(ascent),
    italic_angle: match font.post() {
      Ok(Some(post)) => post.italic_angle.to_double() / 65536
      _ => 0
    },
  })
  self.font_bytes += bytes.length()
  self.paragraphs.clear()
  self.text_units = 0
  self.pagination = None
  self.fonts.length() - 1
}

///|
pub fn TextProbe::font_bytes(
  self : TextProbe,
  index : Int32,
) -> Bytes raise @failure.Failure {
  self.check()
  guard index >= 0 && index < self.fonts.length() else {
    @failure.reject("missing-font", "Unknown font")
  }
  let font = self.fonts[index]
  guard (font.fs_type & 0x0302) == 0 else {
    @failure.reject(
      "unsupported-font-embedding", "Font embedding or subsetting is restricted by OS/2 fsType",
    )
  }
  font.bytes
}

///|
pub fn TextProbe::font_index(
  self : TextProbe,
  identity : String,
) -> Int32 raise @failure.Failure {
  self.check()
  for index, font in self.fonts {
    if font.identity == identity {
      return index
    }
  }
  @failure.reject("missing-font", "Missing font: " + identity)
}

///|
pub fn TextProbe::outline_resources(
  self : TextProbe,
) -> Array[Outline] raise @failure.Failure {
  self.check()
  self.outlines.iter().map(pair => { key: pair.0, path: pair.1, }).collect()
}

///|
pub fn TextProbe::font_info(
  self : TextProbe,
) -> Array[FontInfo] raise @failure.Failure {
  self.check()
  self.fonts.map(font => {
    identity: font.identity,
    face: 0,
    variation: "default",
    upem: font.upem,
    sha256: font.sha256,
    ascent: font.ascent,
    descent: font.descent,
    bbox: font.bbox,
    capHeight: font.cap_height,
    italicAngle: font.italic_angle,
  })
}

///|
pub fn TextProbe::glyph_width(
  self : TextProbe,
  index : Int32,
  glyph : UInt32,
) -> Double raise @failure.Failure {
  self.check()
  guard index >= 0 && index < self.fonts.length() else {
    @failure.reject("missing-font", "Unknown font")
  }
  let font = self.fonts[index]
  match font.font.glyph_h_advance(glyph) {
    Ok(width) => width.to_double() * 1000 / font.upem.to_double()
    Err(_) => @failure.reject("malformed-font", "Invalid glyph advance")
  }
}

///|
fn TextProbe::line_metrics(
  self : TextProbe,
  index : Int32,
  size : Double,
  leading~ : Bool = false,
) -> (Double, Double) {
  let font = self.fonts[index]
  if leading {
    // ONLYOFFICE CTextMetrics adds the source font's line gap above the baseline.
    let scale = size / font.upem.to_double()
    return (
      (font.ascent + font.line_gap).to_double() * scale,
      font.descent.to_double() * scale,
    )
  }
  scaled_line_metrics(font.ascent, font.descent, font.upem, size)
}

///|
fn scaled_line_metrics(
  ascent : Int32,
  descent : Int32,
  upem : Int32,
  size : Double,
) -> (Double, Double) {
  // LibreOffice MSO1 rounds font metrics at 8640 DPI before converting to twips.
  let scale = (size * 120).round() / upem.to_double()
  let ascent = (ascent.to_double() * scale).round()
  let descent = (descent.to_double() * scale).round()
  let baseline = (ascent / 6).round() / 20
  let height = ((ascent + descent) / 6).round() / 20
  (baseline, height - baseline)
}

///|
fn TextProbe::outline(
  self : TextProbe,
  index : Int32,
  glyph : UInt32,
) -> (String, String, Bool) raise @failure.Failure {
  let key = "\{self.fonts[index].sha256}:\{glyph}"
  if self.outlines.get(key) is Some(path) {
    return (key, path, false)
  }
  let pen : GlyphOutlinePen = {
    path: StringBuilder(),
    bounds: [],
    valid: true,
  }
  let funcs = @draw.DrawFuncs::new()
  funcs.set_move_to(
    Some((pen : GlyphOutlinePen, _, x, y) => {
      pen.point(x, y)
      pen.path <+ "M\{x} \{y}"
    }),
  )
  funcs.set_line_to(
    Some((pen, _, x, y) => {
      pen.point(x, y)
      pen.path <+ "L\{x} \{y}"
    }),
  )
  funcs.set_quadratic_to(
    Some((pen, _, x1, y1, x, y) => {
      pen.point(x1, y1)
      pen.point(x, y)
      pen.path <+ "Q\{x1} \{y1} \{x} \{y}"
    }),
  )
  funcs.set_cubic_to(
    Some((pen, _, x1, y1, x2, y2, x, y) => {
      pen.point(x1, y1)
      pen.point(x2, y2)
      pen.point(x, y)
      pen.path <+ "C\{x1} \{y1} \{x2} \{y2} \{x} \{y}"
    }),
  )
  funcs.set_close_path(Some((pen, _) => pen.path.write_char('Z')))
  match self.fonts[index].font.draw_glyph_or_fail(glyph, funcs, pen) {
    Err(_) => @failure.reject("malformed-font", "Glyph outline parsing failed")
    Ok(false) =>
      @failure.reject("unsupported-font", "Glyph has no supported outline")
    Ok(true) => ()
  }
  guard pen.valid else {
    @failure.reject("malformed-font", "Glyph outline coordinates exceed budget")
  }
  let path = pen.path.to_string()
  guard path.length() <= 8388608 - self.outline_bytes else {
    @failure.reject("limit-exceeded", "Outline cache budget exceeded")
  }
  self.outline_bytes += path.length()
  self.outlines[key] = path
  self.outline_boxes[key] = pen.bounds.copy()
  (key, path, true)
}

///|
pub fn TextProbe::close(self : TextProbe) -> Unit {
  self.closed = true
  self.measured_shape = None
  self.fonts.clear()
  self.outlines.clear()
  self.outline_boxes.clear()
  self.paragraphs.clear()
  self.text_units = 0
  self.pagination = None
  self.font_bytes = 0
  self.outline_bytes = 0
}
