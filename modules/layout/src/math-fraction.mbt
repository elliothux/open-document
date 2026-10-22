///|
fn measure_math_fraction(
  numerator : MathBox,
  denominator : MathBox,
  style : TextStyle,
  probe : TextProbe,
  profile : Map[String, String],
) -> MathBox raise @failure.Failure {
  let index = probe.math_font_index(style, profile)
  let (ascent, descent) = probe.line_metrics(index, style.size)
  let height = ascent + descent
  let axis = 0.6 * probe.math_glyph_height(index, 0x2217, style.size)
  let num_gap = (height / 3.05 - descent).max(height / 9.77)
  let den_gap = (height / 2.03 - (ascent - style.size * 7 / 18)).max(
    height / 6.1,
  )
  let rule = style.size * 0.06
  let width = numerator.width.max(denominator.width)
  let num_bottom = numerator.height + num_gap
  let primitives : Array[PositionedPrimitive] = []
  numerator.place(primitives, (width - numerator.width) / 2, 0)
  denominator.place(
    primitives,
    (width - denominator.width) / 2,
    num_bottom + den_gap,
  )
  primitives.push(
    Rectangle({
      x: 0,
      y: num_bottom - rule,
      width,
      height: rule,
      color: style.color,
    }),
  )
  {
    width,
    height: num_bottom + den_gap + denominator.height,
    ascent: num_bottom + axis,
    primitives,
    textAscent: None,
  }
}
