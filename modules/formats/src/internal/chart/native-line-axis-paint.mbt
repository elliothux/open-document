///|
fn line_value_label(
  text : String,
  style : @layout.TextStyle,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> @layout.TextBlock raise @failure.Failure {
  let block = probe.text_block(text, style, profile, 14400, false)
  let shaped = probe.shape(
    text,
    style.size,
    "und",
    primary=line_font(style, probe, profile),
    kerning=style.kerning,
  )
  let unit = 16384.0 * 25.4 / 72
  // ONLYOFFICE CRunText.SetWidth truncates each character to 1/16384 millimeter.
  let width = shaped.glyphs
    .mapi((i, glyph) => {
      let next = shaped.glyphs
        .get(i + 1)
        .map(glyph => glyph.x)
        .unwrap_or(shaped.width)
      ((next - glyph.x) * unit).floor() / unit
    })
    .fold(init=0.0, (total, width) => total + width)
  {
    ..block,
    widths: [width],
    lines: block.lines.map(line => {
      let painted : Array[@layout.PositionedPrimitive] = line.map(primitive => {
        match primitive {
          @layout.Path(
            [Move(left, y), Line(right, at)],
            fill,
            stroke,
            pen,
            style,
          ) if y == at &&
            left == 0 &&
            (right - block.widths[0]).abs() < 0.000001 =>
            @layout.Path(
              [Move(left, y), Line(width, at)],
              fill,
              stroke,
              pen,
              style,
            )
          _ => primitive
        }
      })
      painted
    }),
  }
}

///|
fn line_axis_range(
  axis : NativeLineAxis,
  data : @layout.ChartData,
) -> (Double, Double, Double) raise @failure.Failure {
  let (low, high, step) = line_scale(data, scatter=data.kind == "scatter")
  let low = axis.minimum.unwrap_or(low)
  let high = axis.maximum.unwrap_or(high)
  guard high > low else {
    @failure.reject("unsupported-chart", "Native line axis range is reversed")
  }
  let step = if axis.minimum is Some(_) || axis.maximum is Some(_) {
    let rough = (high - low) / 10
    let unit = @math.pow(10, @math.log10(rough).floor())
    let ratio = rough / unit
    unit *
    (if ratio <= 1 {
      1.0
    } else if ratio <= 2 {
      2.0
    } else if ratio <= 5 {
      5.0
    } else {
      10.0
    })
  } else {
    step
  }
  let ticks = (high - low) / step
  guard !ticks.is_nan() &&
    !ticks.is_inf() &&
    ticks >= 1 &&
    ticks <= 600 &&
    (ticks - ticks.round()).abs() < 0.000001 else {
    @failure.reject("limit-exceeded", "Native line tick count exceeds budget")
  }
  (low, high, step)
}

///|
fn line_axis_tick(
  out : Array[@layout.PathSegment],
  x : Double,
  y : Double,
  pen : (String, Double),
  kind : String,
  right : Bool,
  length~ : Double = 3.75,
  vertical~ : Bool = false,
) -> Unit {
  if kind == "none" || pen.0.is_empty() {
    return
  }
  let sign = if right { 1.0 } else { -1.0 }
  let inward = if kind == "in" || kind == "cross" {
    -sign * length
  } else {
    0.0
  }
  let outward = if kind == "out" || kind == "cross" {
    sign * length
  } else {
    0.0
  }
  out.append(
    if vertical {
      [Move(x, y + inward), Line(x, y + outward)]
    } else {
      [Move(x + inward, y), Line(x + outward, y)]
    },
  )
}

///|
fn line_minor_grid(
  out : Array[@layout.PositionedPrimitive],
  tick_paths : Array[@layout.PathSegment],
  plot : @layout.Border,
  axis : NativeLineAxis,
  ticks : Int32,
  right : Bool,
) -> Unit {
  if axis.minor.0.is_empty() && axis.minor_tick == "none" {
    return
  }
  for i in 0..<(ticks * 5) {
    let y = plot.y + plot.height * (1 - i.to_double() / (ticks * 5).to_double())
    if !axis.minor.0.is_empty() {
      out.push(
        line_path([Move(plot.x, y), Line(plot.x + plot.width, y)], axis.minor),
      )
    }
    line_axis_tick(
      tick_paths,
      if right {
        plot.x + plot.width
      } else {
        plot.x
      },
      y,
      axis.pen,
      axis.minor_tick,
      right,
      length=2.25,
    )
  }
}

///|
fn line_caption_place(
  out : Array[@layout.PositionedPrimitive],
  title : NativeLineTitle,
  x : Double,
  y : Double,
  probe : @layout.TextProbe,
  profile : Map[String, String],
  frame~ : (Double, Double)? = None,
) -> Unit raise @failure.Failure {
  let block = line_value_label(title.text, title.style, probe, profile)
  let width = block.widths[0]
  let inset_x = 2.88 + 0.5 * 72 / 25.4
  let inset_y = 1.44
  let limit = frame.map(size => {
    (
      (size.0 - width - 2.25 * 72 / 25.4).max(0),
      (size.1 - block.height - 2.88).max(0),
    )
  })
  if title.position is Some((left, top)) &&
    frame is Some((width, height)) &&
    limit is Some((max_left, max_top)) {
    line_place(
      out,
      block,
      (left * width).min(max_left) + inset_x,
      (top * height).min(max_top) + inset_y,
    )
    return
  }
  if title.rotation == 0 {
    // Native chart text centers in a box measured at bodyPr.rot, even when glyphs stay horizontal.
    let w = width + 72 / 25.4
    let c = @math.cos(title.angle).abs()
    let s = @math.sin(title.angle).abs()
    let bounds_width = w * c + block.height * s + 1.25 * 72 / 25.4
    let bounds_height = w * s + block.height * c + 2.88
    let x = x - bounds_width / 2 + 2.88 + 0.5 * 72 / 25.4
    let y = y + (bounds_height - block.height) / 2
    let (x, y) = if limit is Some((max_left, max_top)) {
      (
        x.max(inset_x).min(max_left + inset_x),
        y.max(inset_y).min(max_top + inset_y),
      )
    } else {
      (x, y)
    }
    line_place(out, block, x, y)
    return
  }
  out.push(
    Transform(
      if title.rotation == -1 {
        { a: 0, b: -1, c: 1, d: 0, e: x, f: y + width / 2, }
      } else {
        { a: 0, b: 1, c: -1, d: 0, e: x + block.height, f: y - width / 2, }
      },
    ),
  )
  out.append(block.lines.flatten())
  out.push(Restore)
}
