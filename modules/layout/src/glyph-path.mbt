///|
priv struct GlyphPathPen {
  path : Array[PathSegment]
  mut current : (Double, Double)
  mut overflow : Bool
}

///|
fn GlyphPathPen::append(
  self : GlyphPathPen,
  segment : PathSegment,
  x : Double,
  y : Double,
) -> Unit {
  if self.path.length() < 8192 {
    self.path.push(segment)
  } else {
    self.overflow = true
  }
  self.current = (x, y)
}

///|
/// Read a glyph outline in font units. Quadratic curves are represented as cubics.
pub fn TextProbe::source_glyph_path(
  self : TextProbe,
  index : Int32,
  glyph : UInt32,
) -> Array[PathSegment] raise @failure.Failure {
  self.check()
  guard self.fonts.get(index) is Some(font) else {
    @failure.reject("missing-font", "Unknown source font")
  }
  let pen : GlyphPathPen = { path: [], current: (0, 0), overflow: false, }
  let funcs = @draw.DrawFuncs::new()
  funcs.set_move_to(
    Some((pen : GlyphPathPen, _, x, y) => pen.append(Move(x, y), x, y)),
  )
  funcs.set_line_to(Some((pen, _, x, y) => pen.append(Line(x, y), x, y)))
  funcs.set_quadratic_to(
    Some((pen, _, a, b, x, y) => {
      let (p, q) = pen.current
      pen.append(
        Cubic(
          (p + 2.0 * a) / 3,
          (q + 2.0 * b) / 3,
          (x + 2.0 * a) / 3,
          (y + 2.0 * b) / 3,
          x,
          y,
        ),
        x,
        y,
      )
    }),
  )
  funcs.set_cubic_to(
    Some((pen, _, a, b, c, d, x, y) => pen.append(Cubic(a, b, c, d, x, y), x, y)),
  )
  funcs.set_close_path(Some((pen, _) => pen.append(Close, 0, 0)))
  guard font.font.draw_glyph_or_fail(glyph, funcs, pen) is Ok(true) else {
    @failure.reject("malformed-font", "Glyph outline parsing failed")
  }
  guard !pen.overflow else {
    @failure.reject("limit-exceeded", "Glyph path exceeds segment budget")
  }
  pen.path
}
