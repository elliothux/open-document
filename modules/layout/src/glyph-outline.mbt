///|
/// Resolve a source font glyph without shaping or changing its position.
pub fn TextProbe::source_glyph(
  self : TextProbe,
  index : Int,
  glyph : Int,
  name : String,
  codepoint : Int,
  symbolic : Bool,
) -> (String, Int) raise @failure.Failure {
  self.check()
  guard index >= 0 && index < self.fonts.length() else {
    @failure.reject("missing-font", "Unknown source font")
  }
  let font = self.fonts[index]
  let id = if glyph >= 0 {
    glyph.reinterpret_as_uint()
  } else if symbolic {
    // Symbolic TrueType fonts use their own cmap, independently of ToUnicode.
    let mut found : UInt? = None
    for code in [codepoint, codepoint + 0xf000] {
      if found is None {
        if font.font.glyph_for_codepoint(code.reinterpret_as_uint())
          is Ok(Some(id)) {
          found = Some(id)
        }
      }
    }
    found.unwrap_or_else(() => {
      @failure.reject("missing-glyph", "Symbolic source glyph is unavailable")
    })
  } else {
    match font.font.glyph_from_name(name) {
      Ok(Some(id)) => id
      _ => {
        guard codepoint >= 0 else {
          @failure.reject(
            "missing-glyph", "Source glyph mapping is unavailable",
          )
        }
        match font.font.glyph_for_codepoint(codepoint.reinterpret_as_uint()) {
          Ok(Some(id)) => id
          _ => @failure.reject("missing-glyph", "Source glyph is unavailable")
        }
      }
    }
  }
  let (outline, _, _) = self.outline(index, id)
  (outline, font.upem)
}
