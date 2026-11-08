///|
fn line_offsets(values : Array[Int32], count : Int32) -> Bool {
  values.length() <= count &&
  values
  .mapi((i, value) => {
    value >= 0 && value < count && (i == 0 || values[i - 1] < value)
  })
  .all(value => value)
}

///|
fn[T] native_visible(
  styles : Array[T],
  data : @layout.ChartData,
  visible : @layout.ChartVisibility?,
) -> (@layout.ChartData, Array[T]) raise @failure.Failure {
  guard styles.length() == data.series.length() else {
    @failure.reject("invalid-chart", "Native chart styles must match series")
  }
  guard visible is Some(visible) else { return (data, styles) }
  guard line_offsets(visible.categories, data.categories.length()) &&
    visible.colors.length() <= 256 &&
    visible.colors.all(worksheet_color_valid) &&
    visible.values.length() == data.series.length() &&
    visible.values
    .mapi((i, indices) => line_offsets(indices, data.series[i].values.length()))
    .all(value => value) else {
    @failure.reject("invalid-chart", "Invalid native line visibility")
  }
  let indices = visible.values
    .mapi((i, values) => (i, values))
    .filter(entry => !entry.1.is_empty())
  let count = indices.fold(init=visible.categories.length(), (count, entry) => {
    count.max(entry.1.length())
  })
  (
    {
      ..data,
      categories: Array::makei(count, i => {
        visible.categories
        .get(i)
        .map(index => data.categories[index])
        .unwrap_or((i + 1).to_string())
      }),
      series: indices.map(entry => {
        ..data.series[entry.0],
        values: Array::makei(count, i => {
          entry.1.get(i).bind(index => data.series[entry.0].values[index])
        }),
      }),
    },
    indices.map(entry => styles[entry.0]),
  )
}

///|
fn line_scale(
  data : @layout.ChartData,
  radar~ : Bool = false,
  scatter~ : Bool = false,
) -> (Double, Double, Double) raise @failure.Failure {
  let values = data.series
    .map(series => series.values.filter_map(value => value))
    .flatten()
  if values.is_empty() {
    return (0, 1, 0.1)
  }
  let low = values.fold(init=values[0], (a, b) => a.min(b))
  let high = values.fold(init=values[0], (a, b) => a.max(b))
  // ONLYOFFICE's ordinary value axes pad the range and choose a 1/2/5 decade step.
  let (first, last) = if low >= 0 {
    (
      if high > 0 && (high - low) / high < 1.0 / 6 {
        low - (high - low) * (if scatter { 0.05 } else { 0.5 })
      } else {
        0.0
      },
      high +
      0.05 *
      (if high > 0 && (high - low) / high < 1.0 / 6 {
        high - low
      } else {
        high
      }),
    )
  } else if high <= 0 {
    (
      low + 0.05 * (low - high),
      if (low - high) / low > 1.0 / 6 {
        0.0
      } else {
        high - (low - high) / 2
      },
    )
  } else {
    (low - 0.05 * (high - low), high + 0.05 * (high - low))
  }
  let mut low = first
  let mut high = last
  if low == high {
    if low < 0 {
      high = 0
    } else {
      low = 0
    }
  }
  let rough = (high - low) / 10
  guard !rough.is_nan() && !rough.is_inf() else {
    @failure.reject("limit-exceeded", "Native line axis exceeds numeric limits")
  }
  if rough == 0 {
    return (0, 1, 0.1)
  }
  let mut unit = 1.0
  while unit * 10 <= rough {
    unit *= 10
  }
  while unit > rough {
    unit /= 10
    guard unit > 0 else {
      @failure.reject("limit-exceeded", "Native line interval underflows")
    }
  }
  let ratio = rough / unit
  let step = unit *
    (if ratio <= 1 {
      1.0
    } else if ratio <= 2 {
      2.0
    } else if ratio <= 5 {
      5.0
    } else {
      10.0
    })
  if radar {
    // Radar keeps the ordinary interval, but removes the 5% range padding.
    low = if values.all(v => v >= 0) {
      first
    } else {
      values.fold(init=values[0], (a, b) => a.min(b))
    }
    let maximum = values.fold(init=values[0], (a, b) => a.max(b))
    high = if maximum > 0 { maximum } else { last }
    if low == high {
      if low < 0 {
        high = 0
      } else {
        low = 0
        high = if high == 0 { 1.0 } else { high }
      }
    }
  }
  low = (low / step).floor() * step
  high = (if radar { (high / step).ceil() } else { (high / step).floor() + 1 }) *
    step
  guard !low.is_inf() &&
    !high.is_inf() &&
    high > low &&
    !((high - low) / step).is_inf() else {
    @failure.reject("limit-exceeded", "Native line ticks exceed numeric limits")
  }
  (low, high, step)
}

///|
fn line_path(
  path : Array[@layout.PathSegment],
  pen : (String, Double),
  fill~ : String = "",
  dash~ : Array[Double] = [],
  miter~ : Double = 8,
  join~ : Int32 = 0,
) -> @layout.PositionedPrimitive {
  @layout.Path(path, fill, pen.0, pen.1, {
    evenOdd: false,
    fillAlpha: 1,
    strokeAlpha: 1,
    dash,
    cap: 0,
    join,
    miter,
  })
}

///|
fn line_tick(value : Double) -> Double raise @failure.Failure {
  if value == 0 {
    return 0
  }
  let mut normalized = value.abs()
  let mut factor = 1.0
  while normalized < 1 {
    normalized *= 10
    factor *= 10
    guard !factor.is_inf() else {
      @failure.reject("limit-exceeded", "Native line tick precision underflows")
    }
  }
  let scaled = normalized * 1000000000
  guard !scaled.is_inf() else {
    @failure.reject(
      "limit-exceeded", "Native line tick precision exceeds numeric limits",
    )
  }
  (if value < 0 { -1.0 } else { 1.0 }) * scaled.round() / 1000000000 / factor
}

///|
fn line_label(
  text : String,
  style : @layout.TextStyle,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> @layout.TextBlock raise @failure.Failure {
  let block = probe.text_block(text, style, profile, 14400, false)
  let width = probe.shape(
      text,
      style.size,
      "und",
      primary=line_font(style, probe, profile),
      kerning=style.kerning,
    ).width
  { ..block, widths: [width], }
}

///|
fn line_font(
  style : @layout.TextStyle,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Int32 raise @failure.Failure {
  let identity = @layout.font_profile_identity(profile, style.font).unwrap_or_else(() => {
      @failure.reject(
        "missing-font",
        "Missing native chart font: " + style.font,
      )
    },
  )
  probe.font_index(identity)
}

///|
fn line_offset(
  style : @layout.TextStyle,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Double raise @failure.Failure {
  let glyphs = probe.shape(
      "A",
      style.size,
      "und",
      primary=line_font(style, probe, profile),
    ).glyphs
  guard glyphs is [glyph] else {
    @failure.reject(
      "missing-glyph", "Native chart axis requires a measurable A",
    )
  }
  let bounds = probe.source_glyph_bounds(glyph.font, glyph.id)
  guard bounds.length() == 4 else {
    @failure.reject("missing-glyph", "Native chart axis requires glyph bounds")
  }
  // Native font measurement encloses the glyph at 72 dpi before applying label offsets.
  ((bounds[3] * glyph.scale).ceil() - (bounds[1] * glyph.scale).floor()) * 0.8
}

///|
fn line_middle(
  block : @layout.TextBlock,
  probe : @layout.TextProbe,
) -> Double raise @failure.Failure {
  let fonts = probe.font_info()
  let mut baseline = 0.0
  let mut ascent = 0.0
  for primitive in block.lines.flatten() {
    if primitive is @layout.Text(text) {
      for run in text.runs {
        baseline = baseline.max(run.baseline)
        for glyph in run.glyphs {
          ascent = ascent.max(
            fonts[glyph.font].ascent.to_double() * glyph.scale,
          )
        }
      }
    }
  }
  baseline + (block.height - baseline) / 2 - ascent / 2
}

///|
fn line_place(
  out : Array[@layout.PositionedPrimitive],
  block : @layout.TextBlock,
  x : Double,
  y : Double,
) -> Unit {
  out.push(Transform({ a: 1, b: 0, c: 0, d: 1, e: x, f: y, }))
  out.append(block.lines.flatten())
  out.push(Restore)
}

///|
fn NativeLineSeries::marker_at(
  self : NativeLineSeries,
  out : Array[@layout.PositionedPrimitive],
  x : Double,
  y : Double,
  open_diamond~ : Bool = false,
  legend~ : Bool = false,
) -> Unit {
  if self.marker == "none" {
    return
  }
  out.push(
    Transform({
      a: 1,
      b: 0,
      c: 0,
      d: 1,
      e: x - self.marker_size / 2,
      f: y - self.marker_size / 2,
    }),
  )
  if ["x", "star", "plus"].contains(self.marker) && !self.marker_fill.is_empty() {
    out.push(
      Rectangle({
        x: 0,
        y: 0,
        width: self.marker_size,
        height: self.marker_size,
        color: self.marker_fill,
      }),
    )
  }
  out.push(
    line_path(
      if self.marker == "diamond" {
        let size = self.marker_size
        if !open_diamond {
          [
            Move(size / 2, 0),
            Line(size, size / 2),
            Line(size / 2, size),
            Line(0, size / 2),
            Close,
          ]
        } else {
          // The plot's left vertex joins two open stroke ends.
          [
            Move(size / 2, size / 2),
            Move(0, size / 2),
            Line(size / 2, 0),
            Line(size, size / 2),
            Line(size / 2, size),
            Line(0, size / 2),
          ]
        }
      } else if self.marker == "square" {
        // Native chart squares return to their first point without closing the stroke.
        let size = self.marker_size
        [
          Move(0, size),
          Line(0, 0),
          Line(size, 0),
          Line(size, size),
          Line(0, size),
        ]
      } else if self.marker == "x" {
        let size = self.marker_size
        [
          Move(size / 2, size / 2),
          Move(0, size),
          Line(size, 0),
          Move(size, size),
          Line(0, 0),
        ]
      } else if self.marker == "star" {
        let size = self.marker_size
        [
          Move(0, 0),
          Line(size, size),
          Move(0, size),
          Line(size, 0),
          ..if self.marker == "star" {
            [@layout.Move(size / 2, size), @layout.Line(size / 2, 0)]
          } else {
            []
          },
        ]
      } else if self.marker == "plus" {
        let size = self.marker_size
        [
          Move(size / 2, size),
          Line(size / 2, 0),
          Move(0, size / 2),
          Line(size, size / 2),
        ]
      } else if self.marker == "triangle" {
        let size = self.marker_size
        if legend {
          [Move(size / 2, 0), Line(size, size), Line(0, size), Close]
        } else {
          let left = size / 2 - size / 3.0.sqrt()
          let right = size / 2 + size / 3.0.sqrt()
          [
            Move(left, size * 5 / 6),
            Line(size / 2, -size / 6),
            Line(right, size * 5 / 6),
            Line(left, size * 5 / 6),
          ]
        }
      } else if self.marker == "dot" || self.marker == "dash" {
        let size = self.marker_size
        let left = if self.marker == "dot" { size / 2 } else { 0.0 }
        [
          Move(left, size * 0.4),
          Line(size, size * 0.4),
          Line(size, size * 0.6),
          Line(left, size * 0.6),
        ]
      } else {
        // Native chart circles start at the right edge and retain an open stroke seam.
        let size = self.marker_size
        let r = size / 2
        let k = (7.0.sqrt() - 1) / 3 * r
        [
          Move(r, r),
          Move(size, r),
          Cubic(size, r, size, r, size, r),
          Cubic(size, r + k, r + k, size, r, size),
          Cubic(r - k, size, 0, r + k, 0, r),
          Cubic(0, r - k, r - k, 0, r, 0),
          Cubic(r + k, 0, size, r - k, size, r),
        ]
      },
      self.marker_pen.unwrap_or(("", 0.75)),
      fill=self.marker_fill,
    ),
  )
  out.push(Restore)
}

///|
pub fn WorksheetChart::paint(
  self : WorksheetChart,
  width : Double,
  height : Double,
  probe : @layout.TextProbe,
  profile : Map[String, String],
  visible~ : @layout.ChartVisibility? = None,
  after_bar3d~ : Bool = false,
  print~ : Bool = false,
) -> Array[@layout.PositionedPrimitive] raise @failure.Failure {
  if self.native_surface is Some(surface) {
    surface.paint(self.data, width, height, probe, profile, visible)
  } else if self.native_bar is Some(bar) {
    bar.paint(self.data, width, height, probe, profile, visible)
  } else if self.native_line is Some(line) {
    line.paint(
      if visible is None {
        self.layout_data()
      } else {
        self.data
      },
      width,
      height,
      probe,
      profile,
      visible,
      after_bar3d,
      print,
    )
  } else if self.native_radar is Some(radar) {
    radar.paint(
      if visible is None {
        self.layout_data()
      } else {
        self.data
      },
      width,
      height,
      visible,
    )
  } else if self.native_area is Some(area) {
    area.paint(
      if visible is None {
        self.layout_data()
      } else {
        self.data
      },
      width,
      height,
      probe,
      profile,
      visible,
      after_bar3d,
    )
  } else if self.native_bubble is Some(bubble) {
    bubble.paint(
      if visible is None {
        self.layout_data()
      } else {
        self.data
      },
      width,
      height,
      probe,
      profile,
      visible,
      after_bar3d,
      print,
    )
  } else if self.native_circular is Some(circular) {
    circular.paint(
      self.data,
      width,
      height,
      probe,
      profile,
      visible,
      after_bar3d,
      print,
      implicit=self.categories.is_empty(),
    )
  } else {
    self.data.paint(width, height, probe, profile, visible~)
  }
}
