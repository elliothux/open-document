///|
fn positioned_cache_units(
  texts : Array[String],
  primitives : Array[PositionedPrimitive],
) -> Int32 {
  let mut units = texts.fold(init=0, (sum, text) => sum + text.length())
  for primitive in primitives {
    units += 16
    match primitive {
      Text(text) => {
        units += text.text.length()
        for run in text.runs {
          units += run.text.length() +
            run.glyphs.fold(init=0, (sum, glyph) => {
              sum + 10 + glyph.outline.length()
            })
        }
      }
      Path(path, _, _, _, _) | TextRule(path, _, _) =>
        units += path.length() * 7
      _ => ()
    }
  }
  units
}
