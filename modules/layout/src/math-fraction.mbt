///|
pub struct MathFraction {
  numerator : String
  denominator : String
  style : TextStyle
  ascent : Double
  primitives : Array[PositionedPrimitive]
}

///|
/// A plain, single-level inline fraction; source formatting belongs to its owning format.
pub fn MathFraction::new(
  numerator : String,
  denominator : String,
  style : TextStyle,
) -> MathFraction {
  { numerator, denominator, style, ascent: 0, primitives: [], }
}

///|
pub impl ToJson for MathFraction with fn to_json(self) {
  {
    "numerator": self.numerator,
    "denominator": self.denominator,
    "style": self.style,
  }
}

///|
pub extend MathFraction with ToJson::{to_json}

///|
fn MathFraction::validate(self : MathFraction) -> Unit raise @failure.Failure {
  validate_math_text([self.numerator, self.denominator], self.style)
}

///|
fn MathFraction::copy(self : MathFraction) -> MathFraction {
  { ..self, primitives: self.primitives.copy(), }
}

///|
fn MathFraction::cache_units(self : MathFraction) -> Int {
  math_cache_units([self.numerator, self.denominator], self.primitives)
}

///|
fn MathFraction::prepare(
  self : MathFraction,
  probe : TextProbe,
  profile : Map[String, String],
) -> DrawingFrame raise @failure.Failure {
  self.validate()
  let index = probe.math_font_index(self.style, profile)
  let style = { ..self.style, size: self.style.size * 0.76, }
  let numerator = probe.text_block(self.numerator, style, profile, 14400, false)
  let denominator = probe.text_block(
    self.denominator,
    style,
    profile,
    14400,
    false,
  )
  let (ascent, descent) = probe.line_metrics(index, style.size)
  let height = ascent + descent
  let axis = 0.6 * probe.math_glyph_height(index, 0x2217, style.size)
  let num_gap = (height / 3.05 - descent).max(height / 9.77)
  let den_gap = (height / 2.03 - (ascent - style.size * 7 / 18)).max(
    height / 6.1,
  )
  let rule = style.size * 0.06
  let width = numerator.widths[0].max(denominator.widths[0])
  let num_bottom = numerator.height + num_gap
  let total = num_bottom + den_gap + denominator.height
  guard width > 0 &&
    width <= 14400 &&
    total <= 14400 &&
    num_bottom + axis <= total else {
    @failure.reject("limit-exceeded", "Fraction exceeds drawing dimensions")
  }
  let primitives : Array[PositionedPrimitive] = []
  for (block, y) in [(numerator, 0.0), (denominator, num_bottom + den_gap)] {
    primitives.push(
      Transform({
        a: 1,
        b: 0,
        c: 0,
        d: 1,
        e: (width - block.widths[0]) / 2,
        f: y,
      }),
    )
    primitives.append(block.lines[0])
    primitives.push(Restore)
  }
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
    height: total,
    anchor: None,
    content: Fraction({ ..self, ascent: num_bottom + axis, primitives, }),
  }
}
