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
  guard self.numerator.length() + self.denominator.length() <= 4096 &&
    [self.numerator, self.denominator].all(text => {
      !text.is_empty() &&
      !text
      .iter()
      .any(ch => ch.to_int() < 32 || ch == '\u2028' || ch == '\u2029')
    }) &&
    !self.style.size.is_nan() &&
    !self.style.size.is_inf() &&
    self.style.size >= 1 &&
    self.style.size <= 409 &&
    self.style.script == "baseline" &&
    self.style.spacing == 0 &&
    !self.style.underline &&
    !self.style.strike &&
    self.style.highlight.is_empty() &&
    !self.style.font.is_empty() &&
    self.style.font.length() <= 1024 &&
    self.style.color.length() == 6 &&
    self.style.color.iter().all(ch => ch.is_ascii_hexdigit()) else {
    @failure.reject(
      "unsupported-math", "Fraction requires bounded plain numerator and denominator text",
    )
  }
}

///|
fn MathFraction::copy(self : MathFraction) -> MathFraction {
  { ..self, primitives: self.primitives.copy(), }
}

///|
fn MathFraction::cache_units(self : MathFraction) -> Int {
  let mut units = self.numerator.length() + self.denominator.length()
  for primitive in self.primitives {
    units += 16
    if primitive is Text(text) {
      units += text.text.length()
      for run in text.runs {
        units += run.text.length() +
          run.glyphs.fold(init=0, (sum, glyph) => {
            sum + 10 + glyph.outline.length()
          })
      }
    }
  }
  units
}

///|
fn MathFraction::prepare(
  self : MathFraction,
  probe : TextProbe,
  profile : Map[String, String],
) -> DrawingFrame raise @failure.Failure {
  self.validate()
  guard profile.get(self.style.font) is Some(identity) else {
    @failure.reject(
      "missing-font",
      "Missing fraction font profile mapping: " + self.style.font,
    )
  }
  let font = probe.fonts[probe.font_index(identity)]
  let style = { ..self.style, size: self.style.size * 0.76, }
  let numerator = probe.text_block(self.numerator, style, profile, 14400, false)
  let denominator = probe.text_block(
    self.denominator,
    style,
    profile,
    14400,
    false,
  )
  let (ascent, descent) = probe.line_metrics(
    probe.font_index(identity),
    style.size,
  )
  let height = ascent + descent
  let bounds = match font.font.glyph_for_codepoint(0x2217) {
    Ok(Some(glyph)) => font.font.glyph_bounds(glyph)
    _ =>
      @failure.reject(
        "missing-font", "Fraction font requires a mathematical asterisk",
      )
  }
  guard bounds is Ok(Some(bounds)) else {
    @failure.reject(
      "malformed-font", "Fraction font has no mathematical axis metrics",
    )
  }
  let axis = 0.6 *
    (bounds.y_max - bounds.y_min).to_double() *
    style.size /
    font.upem.to_double()
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

///|
fn PlacedDrawingFrame::baseline(self : PlacedDrawingFrame) -> Double {
  match self.content {
    Fraction(fraction) => fraction.ascent
    _ => self.height
  }
}
