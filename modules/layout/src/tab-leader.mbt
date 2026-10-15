///|
// ONLYOFFICE centers repeated font glyphs; hyphens use one and a half advances.
fn TextProbe::tab_leader(
  self : TextProbe,
  leader : String,
  font : Int,
  size : Double,
  width : Double,
) -> Array[Glyph] raise @failure.Failure {
  let symbol = match leader {
    "dot" => "."
    "hyphen" => "-"
    "underscore" | "heavy" => "_"
    "middleDot" => "·"
    _ => return []
  }
  if width <= 0.01 {
    return []
  }
  let batch = self.shape(symbol, size, "und", primary=font)
  guard batch.diagnostics.is_empty() && batch.width > 0 else {
    @failure.reject("missing-glyph", "Tab leader requires a visible font glyph")
  }
  let step = batch.width * (if leader == "hyphen" { 1.5 } else { 1.0 })
  let count = (width / step).floor()
  guard count <= 4096 &&
    batch.glyphs.length() <= 4096 &&
    count * batch.glyphs.length().to_double() <= 4096 else {
    @failure.reject("limit-exceeded", "Tab leader exceeds 4096 glyphs")
  }
  let inset = (width - count * step) / 2
  let result : Array[Glyph] = []
  for i in 0..<count.to_int() {
    for glyph in batch.glyphs {
      result.push({
        ..glyph,
        cluster: 0,
        x: inset + i.to_double() * step + glyph.x,
      })
    }
  }
  result
}
