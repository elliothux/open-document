///|
fn NativeArea::paint(
  self : NativeArea,
  source : @layout.ChartData,
  width : Double,
  height : Double,
  probe : @layout.TextProbe,
  profile : Map[String, String],
  visible : @layout.ChartVisibility?,
  after_bar3d : Bool,
) -> Array[@layout.PositionedPrimitive] raise @failure.Failure {
  source.validate_sources()
  let flat = self.flat_plot is Some(_)
  guard source.kind == (if flat { "stackedArea" } else { "percentStackedArea" }) &&
    width >= 180 &&
    width <= 14400 &&
    height >= 150 &&
    height <= 14400 else {
    @failure.reject(
      "layout-overflow", "Native percentage area requires a bounded chart frame",
    )
  }
  let (data, styles) = native_visible(self.series, source, visible)
  let out : Array[@layout.PositionedPrimitive] = [
    Rectangle({ x: 0, y: 0, width, height, color: self.frame_fill, }),
    line_path(
      [Move(0, 0), Line(width, 0), Line(width, height), Line(0, height), Close],
      self.frame_pen,
    ),
  ]
  if data.categories.is_empty() || data.series.is_empty() {
    return out
  }
  let cumulative = Array::make(data.categories.length(), 0.0)
  let normalized = Array::makei(data.categories.length(), i => {
    data.bar_values(i)
  })
  let values = data.series.mapi((index, _) => {
    normalized.mapi((i, column) => {
      cumulative[i] += column[index].unwrap_or(0)
      cumulative[i]
    })
  })
  let minimum = values.fold(init=0.0, (minimum, row) => {
    row.fold(init=minimum, (a, b) => a.min(b))
  })
  let maximum = values.fold(init=0.0, (maximum, row) => {
    row.fold(init=maximum, (a, b) => a.max(b))
  })
  let (low, high, step) = if flat {
    // Native axis extrema stack compact cache positions; geometry keeps original point indices.
    let totals = Array::make(data.categories.length(), 0.0)
    let range : Array[@layout.ChartSeries] = data.series.map(series => {
      let packed = series.values.filter_map(value => value)
      {
        name: "",
        values: Array::makei(data.categories.length(), i => {
          totals[i] += packed.get(i).unwrap_or(0)
          Some(totals[i])
        }),
      }
    })
    line_scale({ ..data, series: range, }, radar=true)
  } else {
    (
      if minimum < 0 {
        -1.0
      } else {
        0.0
      },
      if maximum > 0 || minimum == 0 {
        1.0
      } else {
        0.0
      },
      0.1,
    )
  }
  let ticks = ((high - low) / step).round().to_int()
  guard ticks > 0 && ticks <= 600 else {
    @failure.reject("limit-exceeded", "Native area ticks exceed budget")
  }
  let value_labels = Array::makei(ticks + 1, i => {
    line_label(
      if flat {
        line_tick(low + i.to_double() * step).to_string()
      } else {
        (low * 100 + i.to_double() * 10).round().to_int().to_string() + "%"
      },
      self.value_text,
      probe,
      profile,
    )
  })
  let category_labels = data.categories.map(text => {
    line_label(text, self.category_text, probe, profile)
  })
  let category_title = line_label(
    self.category_title.0,
    self.category_title.1,
    probe,
    profile,
  )
  let value_title = line_label(
    self.value_title.0,
    self.value_title.1,
    probe,
    profile,
  )
  let label_width = value_labels.fold(init=0.0, (width, label) => {
      width.max(label.widths[0])
    }) +
    0.1 * 72 / 25.4
  let label_height = value_labels.fold(init=0.0, (height, label) => {
      height.max(label.height)
    }) +
    0.1 * 72 / 25.4
  let category_height = category_labels.fold(init=0.0, (height, label) => {
    height.max(label.height)
  })
  // Native worksheet printing inherits the preceding 3D bar's final margin.
  let margin = (if !flat && after_bar3d { 17.0 } else { 14.0 }) * 0.75
  // ONLYOFFICE titles reserve their body insets after resolving a quarter-turn to vertical text.
  let inset = 1.016 * 72 / 25.4
  let value_title_width = value_title.height + 4.4 * inset
  let category_title_height = category_title.height + inset
  let value_gap = line_offset(self.value_text, probe, profile) * 1.5
  let category_gap = line_offset(self.category_text, probe, profile)
  let top = self.flat_plot
    .map(rect => rect.y * height)
    .unwrap_or(label_height / 2 + margin / 3)
  let left = self.flat_plot
    .map(rect => rect.x * width + category_labels[0].widths[0] / 2)
    .unwrap_or(margin + value_title_width + label_width + value_gap)
  let right = self.flat_plot
    .map(rect => (rect.x + rect.width) * width)
    .unwrap_or(width - margin) -
    category_labels.last().unwrap().widths[0] / 2
  let bottom = self.flat_plot
    .map(rect => (rect.y + rect.height) * height)
    .unwrap_or(height - margin - category_title_height) -
    category_height -
    category_gap
  // Native stacked-area width fitting scales Y by (n-1)/n around the plot center.
  let fit = if flat {
    (bottom - top) / (2 * data.categories.length().to_double())
  } else {
    0.0
  }
  let top = top + fit
  let bottom = bottom - fit
  let plot : @layout.Border = {
    x: left,
    y: top,
    width: right - left,
    height: bottom - top,
  }
  guard plot.width > 12 &&
    plot.height > 12 &&
    category_title.widths[0] + 2.25 * 72 / 25.4 <= width - 2 * margin &&
    value_title.widths[0] + 72 / 25.4 + 2 * inset <= plot.height else {
    @failure.reject(
      "layout-overflow", "Native area labels exceed the chart frame",
    )
  }
  let background : @layout.Border = if flat {
    plot
  } else {
    {
      x: plot.x - 0.75,
      y: plot.y - 0.75,
      width: plot.width + 0.75,
      height: plot.height + 0.75,
    }
  }
  if flat && !self.floor_pen.0.is_empty() {
    // At zero rotation the floor collapses to one horizontal stroke.
    out.push(
      line_path(
        [Move(left, bottom), Line(right, bottom)],
        self.floor_pen,
        miter=10,
      ),
    )
  }
  if !self.plot_fill.is_empty() {
    out.push(
      Rectangle({
        x: background.x,
        y: background.y,
        width: background.width,
        height: background.height,
        color: self.plot_fill,
      }),
    )
  }
  for i in 0..<=ticks {
    let y = plot.y + plot.height * (1 - i.to_double() / ticks.to_double())
    if !self.grid_pen.0.is_empty() {
      out.push(line_path([Move(left, y), Line(right, y)], self.grid_pen))
    }
  }
  if !self.plot_pen.0.is_empty() {
    out.push(Stroke(background, self.plot_pen.0, self.plot_pen.1))
  }
  if flat && !self.category_grid.0.is_empty() {
    for i in 0..<data.categories.length() {
      let x = if data.categories.length() == 1 {
        (left + right) / 2
      } else {
        left +
        plot.width * i.to_double() / (data.categories.length() - 1).to_double()
      }
      out.push(line_path([Move(x, top), Line(x, bottom)], self.category_grid))
    }
  }
  // Native area clipping starts one CSS pixel above the plot, without extending its height.
  if !flat {
    out.push(Clip({ ..plot, y: plot.y - 0.75, }))
  }
  let xs = Array::makei(data.categories.length(), i => {
    if data.categories.length() == 1 {
      (left + right) / 2
    } else {
      left +
      plot.width * i.to_double() / (data.categories.length() - 1).to_double()
    }
  })
  let baseline = plot.y + plot.height * (1 - (0.0 - low) / (high - low))
  let y_at = fn(value : Double) {
    let fraction = (value - low) / (high - low)
    plot.y +
    plot.height * (1 - (if flat { fraction.max(0).min(1) } else { fraction }))
  }
  // ONLYOFFICE draws the collapsed upper/lower depth faces before the front faces.
  if flat {
    for index, row in values {
      let fill = styles[index].fill
      if fill.is_empty() || data.series[index].values[0] is None {
        continue
      }
      let shade = line_color_effect(fill, 0.45, false)
      for upper in [false, true] {
        for i in 1..<xs.length() {
          let a = y_at(
            if upper {
              row[i - 1]
            } else if index == 0 {
              0.0
            } else {
              values[index - 1][i - 1]
            },
          )
          let b = y_at(
            if upper {
              row[i]
            } else if index == 0 {
              0.0
            } else {
              values[index - 1][i]
            },
          )
          out.push(
            line_path(
              [
                Move(xs[i - 1], a),
                Line(xs[i - 1], a),
                Line(xs[i], b),
                Line(xs[i], b),
                Line(xs[i - 1], a),
              ],
              (shade, 0.2 * 72 / 25.4),
              fill=shade,
              miter=10,
            ),
          )
        }
      }
    }
  }
  for index, row in values {
    let ys = row.map(y_at)
    if flat {
      let fill = styles[index].fill
      if fill.is_empty() || data.series[index].values[0] is None {
        continue
      }
      for i in 1..<xs.length() {
        let a = if index == 0 {
          baseline
        } else {
          y_at(values[index - 1][i - 1])
        }
        let b = if index == 0 { baseline } else { y_at(values[index - 1][i]) }
        out.push(
          line_path(
            [
              Move(xs[i - 1], ys[i - 1]),
              Line(xs[i - 1], a),
              Line(xs[i], b),
              Line(xs[i], ys[i]),
              Line(xs[i - 1], ys[i - 1]),
            ],
            (fill, 0.2 * 72 / 25.4),
            fill~,
            miter=10,
          ),
        )
      }
      continue
    }
    let path : Array[@layout.PathSegment] = xs.mapi((i, x) => {
      if i == 0 {
        Move(x, ys[i])
      } else {
        Line(x, ys[i])
      }
    })
    if index == 0 {
      path.push(Line(xs.last().unwrap(), baseline))
      path.push(Line(xs[0], baseline))
    } else {
      for offset in 0..<xs.length() {
        let i = xs.length() - 1 - offset
        let y = plot.y +
          plot.height * (1 - (values[index - 1][i] - low) / (high - low))
        path.push(Line(xs[i], y))
      }
    }
    path.push(Line(xs[0], ys[0]))
    out.push(line_path(path, styles[index].pen, fill=styles[index].fill))
  }
  if !flat {
    out.push(Restore)
  }
  out.push(
    line_path([Move(left, baseline), Line(right, baseline)], self.category_pen),
  )
  for i, label in category_labels {
    let path : Array[@layout.PathSegment] = []
    line_axis_tick(
      path,
      xs[i],
      baseline,
      self.category_pen,
      self.category_tick,
      true,
      vertical=true,
    )
    if i + 1 < xs.length() {
      line_axis_tick(
        path,
        (xs[i] + xs[i + 1]) / 2,
        baseline,
        self.category_pen,
        self.category_minor_tick,
        true,
        length=2.25,
        vertical=true,
      )
    }
    if !path.is_empty() {
      out.push(
        line_path(
          path,
          (
            if self.category_pen.0 == "000000" {
              "868686"
            } else {
              self.category_pen.0
            },
            self.category_pen.1,
          ),
        ),
      )
    }
    line_place(out, label, xs[i] - label.widths[0] / 2, baseline + category_gap)
  }
  if !flat {
    out.push(line_path([Move(left, top), Line(left, bottom)], self.value_pen))
  }
  for i, label in value_labels {
    if flat {
      break
    }
    let y = plot.y + plot.height * (1 - i.to_double() / ticks.to_double())
    let path : Array[@layout.PathSegment] = []
    line_axis_tick(path, left, y, self.value_pen, self.value_tick, false)
    if !path.is_empty() {
      out.push(
        line_path(
          path,
          (
            if self.value_pen.0 == "000000" {
              "868686"
            } else {
              self.value_pen.0
            },
            self.value_pen.1,
          ),
        ),
      )
    }
    line_place(
      out,
      label,
      left - value_gap - label.widths[0] - 0.1 * 72 / 25.4,
      y - (label.height + 0.1 * 72 / 25.4) / 2,
    )
  }
  if !flat && self.value_minor_tick != "none" {
    let path : Array[@layout.PathSegment] = []
    for i in 0..<(ticks * 5) {
      let y = plot.y +
        plot.height * (1 - i.to_double() / (ticks * 5).to_double())
      line_axis_tick(
        path,
        left,
        y,
        self.value_pen,
        self.value_minor_tick,
        false,
        length=2.25,
      )
    }
    if !path.is_empty() {
      out.push(
        line_path(
          path,
          (
            if self.value_pen.0 == "000000" {
              "868686"
            } else {
              self.value_pen.0
            },
            self.value_pen.1,
          ),
        ),
      )
    }
  }
  line_place(
    out,
    category_title,
    (left + right - category_title.widths[0]) / 2 + inset - 1.25 * 72 / 25.4 / 2,
    height -
    (if flat { 0.0 } else { margin }) -
    category_title_height +
    inset / 2,
  )
  out.push(
    Transform({
      a: 0,
      b: -1,
      c: 1,
      d: 0,
      // Native 3D text uses the final 17px margin after geometry fitting.
      e: (if flat { 17.0 * 0.75 } else { margin }) +
      (value_title_width - value_title.height) / 2,
      f: (top + bottom + value_title.widths[0]) / 2 + 0.5 * 72 / 25.4,
    }),
  )
  line_place(out, value_title, 0, 0)
  out.push(Restore)
  out
}
