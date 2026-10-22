///|
pub struct MathScripts {
  base : String
  subscript : String
  superscript : String
  style : TextStyle
  ascent : Double
  primitives : Array[PositionedPrimitive]
}

///|
/// Plain inline mathematical subscripts, superscripts, or both.
pub fn MathScripts::new(
  base : String,
  subscript : String,
  superscript : String,
  style : TextStyle,
) -> MathScripts {
  { base, subscript, superscript, style, ascent: 0, primitives: [], }
}

///|
pub impl ToJson for MathScripts with fn to_json(self) {
  {
    "base": self.base,
    "subscript": self.subscript,
    "superscript": self.superscript,
    "style": self.style,
  }
}

///|
pub extend MathScripts with ToJson::{to_json}

///|
fn MathScripts::validate(self : MathScripts) -> Unit raise @failure.Failure {
  guard !self.base.is_empty() &&
    (!self.subscript.is_empty() || !self.superscript.is_empty()) else {
    @failure.reject(
      "unsupported-math", "Script requires a base and at least one index",
    )
  }
  validate_math_text(
    [self.base, self.subscript, self.superscript].filter(text => {
      !text.is_empty()
    }),
    self.style,
  )
}

///|
fn MathScripts::copy(self : MathScripts) -> MathScripts {
  { ..self, primitives: self.primitives.copy(), }
}

///|
fn MathScripts::cache_units(self : MathScripts) -> Int {
  math_cache_units(
    [self.base, self.subscript, self.superscript],
    self.primitives,
  )
}

///|
fn MathScripts::text(self : MathScripts) -> String {
  self.base +
  (if self.subscript.is_empty() { "" } else { "_(" + self.subscript + ")" }) +
  (if self.superscript.is_empty() { "" } else { "^(" + self.superscript + ")" })
}

///|
fn MathScripts::prepare(
  self : MathScripts,
  probe : TextProbe,
  profile : Map[String, String],
) -> DrawingFrame raise @failure.Failure {
  self.validate()
  let index = probe.math_font_index(self.style, profile)
  let base = probe.text_block(self.base, self.style, profile, 14400, false)
  let style = { ..self.style, size: self.style.size * 0.76, }
  let lower = if self.subscript.is_empty() {
    None
  } else {
    Some(probe.text_block(self.subscript, style, profile, 14400, false))
  }
  let upper = if self.superscript.is_empty() {
    None
  } else {
    Some(probe.text_block(self.superscript, style, profile, 14400, false))
  }
  let (base_ascent, _) = probe.line_metrics(index, self.style.size)
  let (script_ascent, _) = probe.line_metrics(index, style.size)
  let placeholder = probe.math_glyph_height(index, 0x2b1a, self.style.size)
  // ONLYOFFICE degree.js uses text-base shifts and a minimum gap for paired indices.
  let (ascent, height, base_y, lower_y, upper_y, gap) = match (lower, upper) {
    (None, Some(upper)) => {
      let plh = 0.64 * placeholder
      let rise = 0.75 * plh
      let (base_y, upper_y) = if base_ascent -
        rise +
        (upper.height - script_ascent) >
        base_ascent - 2.0 / 9 * plh {
        (upper.height - (base_ascent - 2.0 / 9 * plh), 0.0)
      } else if rise + script_ascent > base_ascent {
        (rise + script_ascent - base_ascent, 0.0)
      } else {
        (0.0, base_ascent - rise - script_ascent)
      }
      (
        base_y + base_ascent,
        base_y + base.height,
        base_y,
        0.0,
        upper_y,
        0.056 * plh,
      )
    }
    (Some(lower), None) => {
      let plh = 0.64 * placeholder
      let down = 0.9 *
        0.6 *
        probe.math_glyph_height(index, 0x2217, self.style.size)
      let lower_y = (if script_ascent - down > 0.75 * plh {
          0.25 * plh
        } else {
          plh + down - script_ascent
        }) +
        (base_ascent - plh).max(0)
      (
        base_ascent,
        base.height.max(lower_y + lower.height),
        0.0,
        lower_y,
        0.0,
        0.056 * plh,
      )
    }
    (Some(lower), Some(upper)) => {
      let plh = 0.26 * placeholder
      let between = (3.034 * plh -
      script_ascent -
      (upper.height - script_ascent)).max(0.5 * plh)
      let indices_ascent = upper.height + between + plh
      let ascent = indices_ascent.max(base_ascent)
      let descent = (upper.height + lower.height + between - indices_ascent).max(
        base.height - base_ascent,
      )
      let upper_y = ascent - indices_ascent
      (
        ascent,
        ascent + descent,
        ascent - base_ascent,
        upper_y + upper.height + between,
        upper_y,
        0.14 * plh,
      )
    }
    _ => abort("Validated mathematical script is empty")
  }
  let script_width = lower
    .map(block => block.widths[0])
    .unwrap_or(0)
    .max(upper.map(block => block.widths[0]).unwrap_or(0))
  let width = base.widths[0] + gap + script_width
  guard width > 0 &&
    width <= 14400 &&
    height > 0 &&
    height <= 14400 &&
    ascent <= height else {
    @failure.reject(
      "limit-exceeded", "Mathematical scripts exceed drawing dimensions",
    )
  }
  let blocks = [(base, 0.0, base_y)]
  if lower is Some(block) {
    blocks.push((block, base.widths[0] + gap, lower_y))
  }
  if upper is Some(block) {
    blocks.push((block, base.widths[0] + gap, upper_y))
  }
  let primitives : Array[PositionedPrimitive] = []
  for (block, x, y) in blocks {
    primitives.push(Transform({ a: 1, b: 0, c: 0, d: 1, e: x, f: y, }))
    primitives.append(block.lines[0])
    primitives.push(Restore)
  }
  {
    width,
    height,
    anchor: None,
    content: Scripts({ ..self, ascent, primitives, }),
  }
}
