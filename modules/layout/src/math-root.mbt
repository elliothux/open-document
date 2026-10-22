///|
fn measure_math_root(
  degree : MathBox?,
  base : MathBox,
  style : TextStyle,
  probe : TextProbe,
  profile : Map[String, String],
) -> MathBox raise @failure.Failure {
  let index = probe.math_font_index(style, profile)
  let digit = probe.math_glyph_height(index, 0x35, style.size)
  let descent = probe.math_glyph_metrics(index, 0x67, style.size).1
  let argument_gap = digit * 0.015
  let needed = base.height + argument_gap
  // ONLYOFFICE radical.js selects sign heights from the measured digit, then extends tall signs.
  let heights = [1.07, 1.45, 2.8, 4.08, 5.7, 7.15].map(scale => digit * scale)
  let mut sign_height = needed
  let mut extended = true
  for i, height in heights {
    if needed < height && (i != 0 || base.height - base.ascent <= 0.9 * descent) {
      sign_height = height
      extended = false
      break
    }
  }
  let pt_per_mm = 72.0 / 25.4
  let tick = 0.27438 * style.size * pt_per_mm
  let (tick_height, slash_width, left_gap) = if needed > 7.03 * tick {
    (1.2 * tick, 0.67 * tick, 0.2 * tick)
  } else {
    let scale = if sign_height < heights[1] {
      0.75
    } else if needed < heights[1] {
      0.82
    } else {
      0.868
    }
    let h = if needed < heights[1] { heights[1] } else { sign_height }
    (
      0.6 * tick * (1 + (h - 1.13 * tick) / (2 * 7.03 * tick)),
      tick * scale,
      0.127 * tick,
    )
  }
  let sign_width = slash_width + left_gap + base.width
  let top = ((sign_height - base.height) / 2).max(0)
  let base_gap = argument_gap.max(2)
  let (degree_width, degree_gap, total, degree_y) = match degree {
    None => (0.0, 0.0, sign_height, 0.0)
    Some(degree) => {
      let index_height = degree.height +
        (0.65 * sign_height / pt_per_mm).round() * pt_per_mm
      let total = sign_height.max(index_height)
      (
        (degree.width - 0.13 * style.size * pt_per_mm).max(0),
        0.011 * style.size * pt_per_mm,
        total,
        total - index_height,
      )
    }
  }
  let sign_y = total - sign_height
  let base_y = sign_y + base_gap + top
  let width = degree_width + degree_gap + sign_width
  let base_x = width - base.width
  let pen = style.size * 0.01185 * pt_per_mm
  let stroke = 1.8 * pen
  // Proportional overshoot below 11 pt keeps the small sign's rising leg from folding back.
  let overshoot = 0.35 * pt_per_mm * (style.size / 11).min(1)
  let tick_y = sign_y + sign_height - tick_height
  let x2 = degree_width + 1.25 * pen * 0.456
  let y2 = tick_y + 0.03 * style.size * pt_per_mm + 1.25 * pen * 0.89
  let x3 = x2 + 0.03 * style.size * pt_per_mm
  let y3 = y2 - 0.512 * (x3 - x2)
  let y4 = sign_y + sign_height + overshoot
  let shift = 1.25 * pen * 0.2336
  let x4 = if extended {
    degree_width + slash_width - shift
  } else {
    x3 + (y4 - y3) / 1.848 - shift
  }
  let path : Array[PathSegment] = [
    Move(x2, y2),
    Line(x3, y3),
    Line(x4, y4),
    Line(x4 + shift, y4),
    Line(degree_width + slash_width, sign_y + stroke),
    Line(width, sign_y + stroke),
  ]
  let primitives : Array[PositionedPrimitive] = [
    Path(path, "", style.color, stroke, {
      fillAlpha: 1,
      strokeAlpha: 1,
      dash: [],
      cap: 0,
      join: 0,
      miter: 10,
    }),
  ]
  base.place(primitives, base_x, base_y)
  if degree is Some(box) {
    box.place(primitives, degree_gap, degree_y)
  }
  {
    width: width + stroke / 2,
    height: (base_y + base.height).max(y4 + stroke / 2),
    ascent: base_y + base.ascent,
    primitives,
    textAscent: None,
  }
}
