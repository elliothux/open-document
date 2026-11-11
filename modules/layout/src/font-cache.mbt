///|
priv struct ParsedFonts {
  faces : Map[(String, Bool), ParsedFont]
  mut bytes : Int32
}

///|
let parsed_fonts : ParsedFonts = { faces: Map([]), bytes: 0, }

///|
priv struct ParsedFont {
  font : Font
  mut input : (String, (String) -> Bytes raise @failure.Failure)?
}

///|
fn ParsedFonts::wire(
  self : ParsedFonts,
  input : String,
  decode : (String) -> Bytes raise @failure.Failure,
) -> Font? {
  self.faces
  .values()
  .find_first(entry => {
    entry.input is Some((text, decoder)) &&
    physical_equal(decoder, decode) &&
    text == input
  })
  .map(entry => entry.font)
}

///|
fn ParsedFonts::load(
  self : ParsedFonts,
  bytes : Bytes,
  unicode : Bool,
  input : (String, (String) -> Bytes raise @failure.Failure)?,
) -> Font raise @failure.Failure {
  for (_, mode), entry in self.faces {
    if mode == unicode && entry.font.bytes == bytes {
      if input is Some(_) {
        entry.input = input
      }
      return entry.font
    }
  }
  let hash = StringBuilder()
  for byte in @crypto.sha256(bytes) {
    hash.write_string(byte.to_int().to_string(radix=16).pad_start(2, '0'))
  }
  let key = (hash.to_string(), unicode)
  let font = parse_font(bytes, key.0, unicode)
  while self.faces.length() >= FontFaceCount ||
        bytes.length() > FontInputBytes - self.bytes {
    let oldest = self.faces.keys().next().unwrap()
    self.bytes -= self.faces[oldest].font.bytes.length()
    self.faces.remove(oldest)
  }
  self.faces[key] = { font, input, }
  self.bytes += bytes.length()
  font
}

///|
priv struct GlyphOutlines {
  entries : Map[String, (String, Array[Double])]
  mut units : Int32
}

///|
let shared_glyph_outlines : GlyphOutlines = { entries: Map([]), units: 0, }

///|
fn GlyphOutlines::keep(
  self : GlyphOutlines,
  key : String,
  path : String,
  bounds : Array[Double],
) -> Unit {
  let units = key.length() + path.length() + 32
  if units > 8388608 {
    return
  }
  while units > 8388608 - self.units {
    let oldest = self.entries.keys().next().unwrap()
    self.units -= oldest.length() + self.entries[oldest].0.length() + 32
    self.entries.remove(oldest)
  }
  self.entries[key] = (path, bounds)
  self.units += units
}
