///|
fn TextProbe::math_nary_sign(
  self : TextProbe,
  operator : String,
  style : TextStyle,
  profile : Map[String, String],
  paths : Ref[Int],
  display~ : Bool = false,
) -> MathBox raise @failure.Failure {
  let index = self.math_font_index(style, profile)
  let font = self.fonts[index]
  if display {
    guard font.font.get_face().reference_table(@common.Tag::from_string("MATH"))
      is Ok(blob) else {
      @failure.reject(
        "unsupported-font", "Display operators require a MATH font table",
      )
    }
    let data = blob.as_view()
    guard math_u16(data, 0) == 1 && math_u16(data, 4) > 0 else {
      @failure.reject("malformed-font", "Missing mathematical font constants")
    }
    let minimum = math_u16(data, math_u16(data, 4) + 6)
    guard minimum > 0 else {
      @failure.reject(
        "malformed-font", "Invalid display operator minimum height",
      )
    }
    let box = self.math_delimiter(
      index,
      operator,
      minimum.to_double() * style.size / font.upem.to_double(),
      style,
      paths,
    )
    let axis = 0.6 * self.math_glyph_height(index, 0x2217, style.size)
    return { ..box, ascent: box.height / 2 + axis, textAscent: None, }
  }
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
fn measure_math_limits(
  sign : MathBox,
  lower : MathBox?,
  upper : MathBox?,
  size : Double,
) -> MathBox {
  let gap_top = if upper is Some(_) { size * 0.25 * 72 / 96 } else { 0.0 }
  let gap_bottom = lower
    .map(box => (size * 0.23 * 72 / 25.4 - box.ascent).max(size * 0.1 * 72 / 96))
    .unwrap_or(0)
  let upper_height = upper.map(box => box.height).unwrap_or(0)
  let sign_y = upper_height + gap_top
  let lower_y = sign_y + sign.height + gap_bottom
  let width = sign.width
    .max(lower.map(box => box.width).unwrap_or(0))
    .max(upper.map(box => box.width).unwrap_or(0))
  let primitives : Array[PositionedPrimitive] = []
  sign.place(primitives, (width - sign.width) / 2, sign_y)
  if upper is Some(box) {
    box.place(primitives, (width - box.width) / 2, 0)
  }
  if lower is Some(box) {
    box.place(primitives, (width - box.width) / 2, lower_y)
  }
  {
    width,
    height: lower_y + lower.map(box => box.height).unwrap_or(0),
    ascent: sign_y + sign.ascent,
    primitives,
    textAscent: None,
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
