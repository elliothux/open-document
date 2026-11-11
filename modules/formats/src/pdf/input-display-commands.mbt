///|
// Keep native command indices available to source extraction.
fn pdf_display_commands(commands : Array[@layout.DrawCommand]) -> Array[Json] {
  let output : Array[Json] = []
  let mut index = 0
  let mut last_style : @layout.DrawStyle? = None
  while index < commands.length() {
    if commands[index:]
      is [
        Style(style),
        Transform(matrix),
        Glyphs(0, 0, color, [glyph]),
        Restore,
        ..,
      ] &&
      glyph.strokeWidth == 0 {
      if last_style != Some(style) {
        output.push(Json(commands[index]))
        last_style = Some(style)
      }
      let outlines = [glyph.outline]
      let indices = Map([(glyph.outline, 0)])
      let positions = [(0, matrix.e, matrix.f)]
      index += 4
      while commands[index:]
            is [
              Style(next_style),
              Transform(next_matrix),
              Glyphs(0, 0, next_color, [next]),
              Restore,
              ..,
            ] &&
            next_style == style &&
            next_color == color &&
            next_matrix.a == matrix.a &&
            next_matrix.b == matrix.b &&
            next_matrix.c == matrix.c &&
            next_matrix.d == matrix.d &&
            next.upem == glyph.upem &&
            next.fontBounds == glyph.fontBounds &&
            next.strokeWidth == 0 &&
            next.x == glyph.x &&
            next.y == glyph.y &&
            next.scaleX == glyph.scaleX &&
            next.scaleY == glyph.scaleY {
        let key = match indices.get(next.outline) {
          Some(key) => key
          None => {
            let key = outlines.length()
            indices[next.outline] = key
            outlines.push(next.outline)
            key
          }
        }
        positions.push((key, next_matrix.e, next_matrix.f))
        index += 4
      }
      let bounds = match glyph.fontBounds {
        Some(bounds) => ToJson::to_json(bounds)
        None => Json::null()
      }
      output.push({
        "op": "pdfGlyphs",
        "color": color,
        "matrix": (matrix.a, matrix.b, matrix.c, matrix.d),
        "origin": (glyph.x, glyph.y),
        "outlines": outlines,
        "run": (glyph.upem, bounds, 0, glyph.scaleX, glyph.scaleY, positions),
      })
    } else {
      output.push(Json(commands[index]))
      last_style = None
      index += 1
    }
  }
  output
}
