///|
struct Font {
  font : @font.Font
  identity : String
  upem : Int
  bytes : Bytes
  sha256 : String
  ascent : Int
  descent : Int
  fs_type : Int
  bbox : Array[Int]
  cap_height : Int
  italic_angle : Double
}

///|
pub struct TextProbe {
  fonts : Array[Font]
  outlines : Map[String, String]
  mut font_bytes : Int
  mut outline_bytes : Int
  mut closed : Bool
}

///|
pub fn TextProbe::new() -> TextProbe {
  {
    fonts: [],
    outlines: Map([]),
    font_bytes: 0,
    outline_bytes: 0,
    closed: false,
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
) -> Int raise @failure.Failure {
  self.check()
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
  match font.glyph_for_codepoint(32U) {
    Err(_) => @failure.reject("malformed-font", "Invalid font cmap")
    Ok(_) => ()
  }
  font.set_scale(upem, upem)
  let os2 = match font.os2() {
    Ok(Some(table)) => table
    _ => @failure.reject("malformed-font", "Missing or invalid OS/2 metrics")
  }
  let digest = @crypto.sha256(bytes)
  let head_bytes = face
    .reference_table(@common.Tag::from_string("head"))
    .unwrap()
    .as_view()
  guard head_bytes.length() >= 54 && os2.win_ascent + os2.win_descent > 0 else {
    @failure.reject("malformed-font", "Invalid line or bounding metrics")
  }
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
    ascent: os2.win_ascent,
    descent: os2.win_descent,
    fs_type: os2.fs_type,
    bbox,
    cap_height: os2.cap_height.unwrap_or(os2.win_ascent),
    italic_angle: match font.post() {
      Ok(Some(post)) => post.italic_angle.to_double() / 65536
      _ => 0
    },
  })
  self.font_bytes += bytes.length()
  self.fonts.length() - 1
}

///|
pub fn TextProbe::font_bytes(
  self : TextProbe,
  index : Int,
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
) -> Int raise @failure.Failure {
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
  index : Int,
  glyph : UInt,
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
  index : Int,
  size : Double,
) -> (Double, Double) {
  let font = self.fonts[index]
  (
    font.ascent.to_double() * size / font.upem.to_double(),
    font.descent.to_double() * size / font.upem.to_double(),
  )
}

///|
fn TextProbe::outline(
  self : TextProbe,
  index : Int,
  glyph : UInt,
) -> (String, String, Bool) raise @failure.Failure {
  let key = "\{index}:\{glyph}"
  if self.outlines.get(key) is Some(path) {
    return (key, path, false)
  }
  let pen = StringBuilder()
  let funcs = @draw.DrawFuncs::new()
  funcs.set_move_to(Some((pen : StringBuilder, _, x, y) => pen <+ "M\{x} \{y}"))
  funcs.set_line_to(Some((pen, _, x, y) => pen <+ "L\{x} \{y}"))
  funcs.set_quadratic_to(
    Some((pen, _, x1, y1, x, y) => pen <+ "Q\{x1} \{y1} \{x} \{y}"),
  )
  funcs.set_cubic_to(
    Some((pen, _, x1, y1, x2, y2, x, y) => {
      pen <+ "C\{x1} \{y1} \{x2} \{y2} \{x} \{y}"
    }),
  )
  funcs.set_close_path(Some((pen, _) => pen.write_char('Z')))
  match self.fonts[index].font.draw_glyph_or_fail(glyph, funcs, pen) {
    Err(_) => @failure.reject("malformed-font", "Glyph outline parsing failed")
    Ok(false) =>
      @failure.reject("unsupported-font", "Glyph has no supported outline")
    Ok(true) => ()
  }
  let path = pen.to_string()
  guard path.length() <= 8388608 - self.outline_bytes else {
    @failure.reject("limit-exceeded", "Outline cache budget exceeded")
  }
  self.outline_bytes += path.length()
  self.outlines[key] = path
  (key, path, true)
}

///|
pub fn TextProbe::close(self : TextProbe) -> Unit {
  self.closed = true
  self.fonts.clear()
  self.outlines.clear()
  self.font_bytes = 0
  self.outline_bytes = 0
}
