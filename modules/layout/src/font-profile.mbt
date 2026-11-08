///|
fn font_requests_bold(key : String) -> Bool {
  key.split("|").any(part => part == "bold")
}

///|
fn TextProbe::bold_glyphs(
  self : TextProbe,
  glyphs : Array[Glyph],
  key : String,
) -> Array[Glyph] raise @failure.Failure {
  guard font_requests_bold(key) else { return glyphs }
  let strokes : Map[Int32, Double] = Map([])
  glyphs.map(glyph => {
    let strokeWidth = strokes
      .get(glyph.font)
      .unwrap_or_else(() => {
        let width = if self.font_style(glyph.font).0 {
          0.0
        } else {
          // Font units preserve ONLYOFFICE's size / 12 * 0.343 stroke through later scaling.
          self.fonts[glyph.font].upem.to_double() * 0.343 / 12
        }
        strokes[glyph.font] = width
        width
      })
    { ..glyph, strokeWidth, }
  })
}

///|
/// Resolves an exact font mapping, then an explicitly supplied style fallback.
pub fn font_profile_identity(
  profile : Map[String, String],
  key : String,
) -> String? {
  if profile.get(key) is Some(identity) {
    return Some(identity)
  }
  let parts = key.split("|").to_array()
  let fallback = "*" +
    (if parts.contains("bold") { "|bold" } else { "" }) +
    (if parts.contains("italic") { "|italic" } else { "" })
  if profile.get(fallback) is Some(identity) {
    Some(identity)
  } else {
    profile.get("*")
  }
}
