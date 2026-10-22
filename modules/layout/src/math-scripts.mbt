///|
fn measure_math_scripts(
  base : MathBox,
  lower : MathBox?,
  upper : MathBox?,
  style : TextStyle,
  probe : TextProbe,
  profile : Map[String, String],
) -> MathBox raise @failure.Failure {
  let index = probe.math_font_index(style, profile)
  let placeholder = probe.math_glyph_height(index, 0x2b1a, style.size)
  let center = 0.6 * probe.math_glyph_height(index, 0x2217, style.size)
  // ONLYOFFICE degree.js distinguishes a trailing text run from a structured base.
  let (ascent, height, base_y, lower_y, upper_y, gap) = match (lower, upper) {
    (None, Some(upper)) => {
      let plh = 0.64 * placeholder
      let rise = 0.75 * plh
      let (base_y, upper_y) = match base.textAscent {
        Some(last) => {
          let (up_base, up_iter) = if last -
            rise +
            (upper.height - upper.ascent) >
            last - 2.0 / 9 * plh {
            (upper.height - (last - 2.0 / 9 * plh), 0.0)
          } else if rise + upper.ascent > last {
            (rise + upper.ascent - last, 0.0)
          } else {
            (0.0, last - rise - upper.ascent)
          }
          if up_base + last > base.ascent {
            (up_base - (base.ascent - last), up_iter)
          } else {
            (0.0, base.ascent - up_base - last + up_iter)
          }
        }
        None =>
          if upper.height - upper.ascent + center > base.ascent {
            (upper.height - (base.ascent - center), 0.0)
          } else if upper.ascent > center {
            (upper.ascent - center, 0.0)
          } else {
            (0.0, center - upper.ascent)
          }
      }
      (
        base_y + base.ascent,
        base_y + base.height,
        base_y,
        0.0,
        upper_y,
        0.056 * plh,
      )
    }
    (Some(lower), None) => {
      let plh = 0.64 * placeholder
      let lower_y = if base.textAscent is Some(_) {
        (if lower.ascent - 0.9 * center > 0.75 * plh {
          0.25 * plh
        } else {
          plh + 0.9 * center - lower.ascent
        }) +
        (base.ascent - plh).max(0)
      } else {
        (base.height + center - lower.ascent).max(base.ascent - 1.5 * center)
      }
      (
        base.ascent,
        base.height.max(lower_y + lower.height),
        0.0,
        lower_y,
        0.0,
        0.056 * plh,
      )
    }
    (Some(lower), Some(upper)) => {
      let plh = 0.26 * placeholder
      if base.textAscent is Some(_) {
        let between = (3.034 * plh -
        lower.ascent -
        (upper.height - upper.ascent)).max(0.5 * plh)
        let indices_ascent = upper.height + between + plh
        let ascent = indices_ascent.max(base.ascent)
        let descent = (upper.height + lower.height + between - indices_ascent).max(
          base.height - base.ascent,
        )
        let upper_y = ascent - indices_ascent
        (
          ascent,
          ascent + descent,
          ascent - base.ascent,
          upper_y + upper.height + between,
          upper_y,
          0.14 * plh,
        )
      } else {
        let center = 1.4 * center
        let up_gap = (base.ascent - center - (upper.height - upper.ascent + plh)).max(
          0,
        )
        let down_gap = (base.height -
        base.ascent +
        center -
        (lower.ascent - plh)).max(0)
        let between = (up_gap + down_gap).max(0.7 * plh)
        let ascent = upper.height + up_gap + center
        (
          ascent,
          upper.height + between + lower.height,
          ascent - base.ascent,
          upper.height + between,
          0.0,
          0.14 * plh,
        )
      }
    }
    _ => abort("Validated mathematical script is empty")
  }
  let primitives : Array[PositionedPrimitive] = []
  base.place(primitives, 0, base_y)
  if lower is Some(box) {
    box.place(primitives, base.width + gap, lower_y)
  }
  if upper is Some(box) {
    box.place(primitives, base.width + gap, upper_y)
  }
  {
    width: base.width +
    gap +
    lower
    .map(box => box.width)
    .unwrap_or(0)
    .max(upper.map(box => box.width).unwrap_or(0)),
    height,
    ascent,
    primitives,
    textAscent: None,
  }
}
