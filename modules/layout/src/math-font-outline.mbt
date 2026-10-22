///|
fn TextProbe::math_delimiter(
  self : TextProbe,
  index : Int,
  character : String,
  target : Double,
  style : TextStyle,
  budget : Ref[Int],
) -> MathBox raise @failure.Failure {
  if character.is_empty() {
    return { width: 0, height: 0, ascent: 0, primitives: [], textAscent: None, }
  }
  let font = self.fonts[index]
  guard font.font.glyph_for_codepoint(
      character.iter().next().unwrap().to_int().reinterpret_as_uint(),
    )
    is Ok(Some(glyph)) else {
    @failure.reject("missing-font", "Missing delimiter glyph")
  }
  let scale = style.size / font.upem.to_double()
  guard font.font.glyph_bounds(glyph) is Ok(Some(bounds)) else {
    @failure.reject("malformed-font", "Missing delimiter glyph bounds")
  }
  let positions = if (bounds.y_max - bounds.y_min).to_double() * scale >= target {
    [(glyph, 0.0)]
  } else {
    self.math_variant(index, glyph, target / scale)
  }
  let path : Array[PathSegment] = []
  let mut left = 0.0
  let mut right = 0.0
  let mut bottom = 0.0
  let mut top = 0.0
  for (glyph, offset) in positions {
    guard font.font.glyph_bounds(glyph) is Ok(Some(bounds)) &&
      font.font.glyph_h_advance(glyph) is Ok(advance) else {
      @failure.reject("malformed-font", "Invalid delimiter part metrics")
    }
    left = left.min(bounds.x_min.to_double() * scale)
    right = right.max(bounds.x_max.max(advance).to_double() * scale)
    bottom = bottom.min((offset + bounds.y_min.to_double()) * scale)
    top = top.max((offset + bounds.y_max.to_double()) * scale)
    let funcs = @draw.DrawFuncs::new()
    let append = (path : Array[PathSegment], segment) => {
      budget.val += 1
      if path.length() < 8192 && budget.val <= 65536 {
        path.push(segment)
      }
    }
    funcs.set_move_to(
      Some((path, _, x, y) => {
        append(path, Move(x * scale, -(y + offset) * scale))
      }),
    )
    funcs.set_line_to(
      Some((path, _, x, y) => {
        append(path, Line(x * scale, -(y + offset) * scale))
      }),
    )
    funcs.set_cubic_to(
      Some((path, _, x1, y1, x2, y2, x, y) => {
        append(
          path,
          Cubic(
            x1 * scale,
            -(y1 + offset) * scale,
            x2 * scale,
            -(y2 + offset) * scale,
            x * scale,
            -(y + offset) * scale,
          ),
        )
      }),
    )
    funcs.set_close_path(Some((path, _) => append(path, Close)))
    guard font.font.draw_glyph_or_fail(glyph, funcs, path) is Ok(true) else {
      @failure.reject("malformed-font", "Invalid delimiter glyph outline")
    }
    guard path.length() < 8192 && budget.val <= 65536 else {
      @failure.reject(
        "limit-exceeded", "Delimiter outline exceeds mathematical path budget",
      )
    }
  }
  let primitives : Array[PositionedPrimitive] = [
    Transform({ a: 1, b: 0, c: 0, d: 1, e: -left, f: top, }),
    Path(path, style.color, "", 0, {
      fillAlpha: 1,
      strokeAlpha: 1,
      dash: [],
      cap: 0,
      join: 0,
      miter: 10,
    }),
    Restore,
  ]
  {
    width: right - left,
    height: top - bottom,
    ascent: top,
    primitives,
    textAscent: None,
  }
}
