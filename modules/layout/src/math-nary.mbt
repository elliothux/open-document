///|
fn TextProbe::math_nary_sign(
  self : TextProbe,
  operator : String,
  style : TextStyle,
  profile : Map[String, String],
  paths : Ref[Int],
) -> MathBox raise @failure.Failure {
  let index = self.math_font_index(style, profile)
  let font = self.fonts[index]
  guard font.font.glyph_for_codepoint(
      operator.iter().next().unwrap().to_int().reinterpret_as_uint(),
    )
    is Ok(Some(glyph)) &&
    font.font.glyph_bounds(glyph) is Ok(Some(bounds)) &&
    bounds.y_max > 0 &&
    bounds.y_max > bounds.y_min &&
    bounds.x_max > bounds.x_min else {
    @failure.reject(
      "missing-font", "N-ary operator requires actual glyph bounds",
    )
  }
  let text = MathExpression::Text(operator).measure(style, self, profile, paths)
  let scale = style.size / font.upem.to_double()
  let ascent = bounds.y_max.to_double() * scale
  let primitives : Array[PositionedPrimitive] = []
  // ONLYOFFICE's inline n-ary CMathText uses ink width and compensates glyph bearings.
  text.place(
    primitives,
    -bounds.x_min.to_double() * scale,
    ascent - text.ascent,
  )
  {
    width: (bounds.x_max - bounds.x_min).to_double() * scale,
    height: (bounds.y_max - bounds.y_min).to_double() * scale,
    ascent,
    primitives,
    textAscent: Some(ascent),
  }
}

///|
fn measure_math_nary(
  operator : MathBox,
  body : MathBox,
  size : Double,
) -> MathBox {
  // ONLYOFFICE nary.js uses ordinary glyphs with side scripts in inline formulae.
  let gap = size / 36 * 2.45 * 72 / 25.4
  let ascent = operator.ascent.max(body.ascent)
  let descent = (operator.height - operator.ascent).max(
    body.height - body.ascent,
  )
  let primitives : Array[PositionedPrimitive] = []
  operator.place(primitives, 0, ascent - operator.ascent)
  body.place(primitives, operator.width + gap, ascent - body.ascent)
  {
    width: operator.width + gap + body.width,
    height: ascent + descent,
    ascent,
    primitives,
    textAscent: None,
  }
}
