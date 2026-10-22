///|
fn positioned_cache_units(
  texts : Array[String],
  primitives : Array[PositionedPrimitive],
) -> Int {
  let mut units = texts.fold(init=0, (sum, text) => sum + text.length())
  for primitive in primitives {
    units += 16
    if primitive is Text(text) {
      units += text.text.length()
      for run in text.runs {
        units += run.text.length() +
          run.glyphs.fold(init=0, (sum, glyph) => {
            sum + 10 + glyph.outline.length()
          })
      }
    } else if primitive is Path(path, _, _, _, _) {
      units += path.length() * 7
    }
  }
  units
}
