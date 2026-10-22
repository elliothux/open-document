///|
fn validate_math_style(style : TextStyle) -> Unit raise @failure.Failure {
  guard !style.size.is_nan() &&
    !style.size.is_inf() &&
    style.size >= 0.5 &&
    style.size <= 409 &&
    style.script == "baseline" &&
    style.spacing == 0 &&
    !style.underline &&
    !style.strike &&
    style.highlight.is_empty() &&
    !style.font.is_empty() &&
    style.font.length() <= 1024 &&
    style.color.length() == 6 &&
    style.color.iter().all(ch => ch.is_ascii_hexdigit()) else {
    @failure.reject(
      "unsupported-math", "Math requires bounded plain text and uniform formatting",
    )
  }
}

///|
fn math_cache_units(
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

///|
fn TextProbe::math_font_index(
  self : TextProbe,
  style : TextStyle,
  profile : Map[String, String],
) -> Int raise @failure.Failure {
  guard profile.get(style.font) is Some(identity) else {
    @failure.reject(
      "missing-font",
      "Missing mathematical font profile mapping: " + style.font,
    )
  }
  self.font_index(identity)
}

///|
fn TextProbe::math_glyph_metrics(
  self : TextProbe,
  index : Int,
  codepoint : UInt,
  size : Double,
) -> (Double, Double) raise @failure.Failure {
  let font = self.fonts[index]
  let bounds = match font.font.glyph_for_codepoint(codepoint) {
    Ok(Some(glyph)) => font.font.glyph_bounds(glyph)
    _ =>
      @failure.reject(
        "missing-font",
        "Mathematical font requires measurement glyph: " + codepoint.to_string(),
      )
  }
  guard bounds is Ok(Some(bounds)) else {
    @failure.reject(
      "malformed-font", "Mathematical font has no measurement glyph bounds",
    )
  }
  let scale = size / font.upem.to_double()
  (
    (bounds.y_max - bounds.y_min).to_double() * scale,
    (-bounds.y_min).max(0).to_double() * scale,
  )
}

///|
fn TextProbe::math_glyph_height(
  self : TextProbe,
  index : Int,
  codepoint : UInt,
  size : Double,
) -> Double raise @failure.Failure {
  self.math_glyph_metrics(index, codepoint, size).0
}

///|
fn PlacedDrawingFrame::baseline(self : PlacedDrawingFrame) -> Double {
  match self.content {
    Math(formula) => formula.ascent
    _ => self.height
  }
}

///|
/// Linear accessible text for supported mathematical content; other drawings have no math text.
pub fn DrawingContent::math_text(self : DrawingContent) -> String? {
  match self {
    Math(formula) =>
      try {
        formula.expression.check()
        Some(formula.expression.linear_text())
      } catch {
        @failure.Failure(..) => None
      }
    _ => None
  }
}
