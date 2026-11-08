///|
fn NativeBar3d::paint(
  self : NativeBar3d,
  source : @layout.ChartData,
  width : Double,
  height : Double,
  probe : @layout.TextProbe,
  profile : Map[String, String],
  visible : @layout.ChartVisibility?,
) -> Array[@layout.PositionedPrimitive] raise @failure.Failure {
  source.validate_sources()
  guard width >= 180 && width <= 14400 && height >= 150 && height <= 14400 else {
    @failure.reject(
      "layout-overflow", "Three-dimensional bars require a bounded frame",
    )
  }
  let (data, styles) = native_visible(self.series, source, visible)
  let out : Array[@layout.PositionedPrimitive] = []
  if !self.frame.0.is_empty() {
    out.push(Rectangle({ x: 0, y: 0, width, height, color: self.frame.0, }))
  }
  if !self.frame.1.0.is_empty() {
    out.push(
      Stroke({ x: 0, y: 0, width, height, }, self.frame.1.0, self.frame.1.1),
    )
  }
  if data.categories.is_empty() || data.series.is_empty() {
    return out
  }
  let positive = Array::make(data.categories.length(), 0.0)
  let negative = Array::make(data.categories.length(), 0.0)
  if self.horizontal {
    for series in data.series {
      for i, value in series.values {
        if i < positive.length() && value is Some(v) {
          if v >= 0 {
            positive[i] += v
          } else {
            negative[i] += v
          }
        }
      }
    }
  }
  let range_data = if self.horizontal {
    {
      ..data,
      series: [
        { name: "", values: positive.map(v => Some(v)), },
        { name: "", values: negative.map(v => Some(v)), },
      ],
    }
  } else {
    data
  }
  let (low, high, step) = line_scale(range_data, radar=self.horizontal)
  let ticks = ((high - low) / step).round().to_int()
  guard ticks > 0 && ticks <= 600 else {
    @failure.reject(
      "limit-exceeded", "Three-dimensional axis exceeds tick budget",
    )
  }
  let labels = Array::makei(ticks + 1, i => {
    line_value_label(
      line_tick(low + i.to_double() * step).to_string(),
      self.value.text,
      probe,
      profile,
    )
  })
  let categories = data.categories.map(text => {
    line_label(text, self.category.text, probe, profile)
  })
  let legend_labels = self.legend
    .map(legend => {
      data.series.map(series => {
        line_label(
          series.name,
          circular_text_style(legend.text),
          probe,
          profile,
        )
      })
    })
    .unwrap_or([])
  let maximum = fn(blocks : Array[@layout.TextBlock]) {
    blocks.fold(init=0.0, (a, b) => a.max(b.widths[0]))
  }
  let label_height = labels.fold(init=0.0, (a, b) => a.max(b.height))
  let category_height = categories.fold(init=0.0, (a, b) => a.max(b.height))
  let value_gap = line_offset(self.value.text, probe, profile)
  let category_gap = line_offset(self.category.text, probe, profile)
  let marker = self.legend
    .map(legend => circular_text_style(legend.text).size * 0.2 * 72 / 25.4)
    .unwrap_or(0)
  let legend_gap = marker * 0.7
  let legend_width = if self.legend is Some(_) {
    maximum(legend_labels) + marker + 3 * legend_gap
  } else {
    0.0
  }
  let title_height = fn(title : NativeLineTitle?) raise @failure.Failure {
    title
    .map(title => {
      line_value_label(title.text, title.style, probe, profile).height + 2.88
    })
    .unwrap_or(0)
  }
  let title_width = title_height(self.value.title) +
    (if self.value.title is Some(_) { 3.4 * 2.88 } else { 0.0 })
  let margin = 16.0 * 0.75
  let left = margin +
    (if self.horizontal {
      maximum(categories) + category_gap * 1.5
    } else {
      maximum(labels) + value_gap * 1.5 + title_width
    }) +
    0.1 * 72 / 25.4
  let right = width -
    margin -
    (if self.horizontal { maximum(labels) / 2 } else { legend_width })
  let mut bottom = height -
    margin -
    (if self.horizontal {
      label_height + value_gap
    } else {
      category_height +
      category_gap +
      title_height(self.category.title) +
      title_height(self.series_axis.bind(axis => axis.title))
    })
  let mut top = margin +
    (if self.horizontal { 0.0 } else { (label_height + 0.1 * 72 / 25.4) / 2 })
  if self.horizontal {
    // Native axes fit the category labels before and after reserving the value labels.
    let count = categories.length().to_double()
    let label_extent = category_height + 0.1 * 72 / 25.4
    let initial_overhang = ((label_extent - (height - 2 * margin) / count) / 2).max(
      0,
    )
    let final_overhang = ((label_extent - (bottom - top) / count) / 2).max(0)
    top += final_overhang
    bottom += final_overhang - initial_overhang
  }
  let plot : @layout.Border = {
    x: left,
    y: top,
    width: right - left,
    height: bottom - top,
  }
  guard plot.width > 12 && plot.height > 12 else {
    @failure.reject(
      "layout-overflow", "Three-dimensional chart labels exceed its frame",
    )
  }
  let projection = bar_projection(
    (width, height),
    plot,
    self.rotation,
    self.perspective,
    self.depth,
    data.series.length(),
    data.categories.length(),
  )
  let point = fn(x : Double, y : Double, z : Double) {
    projection.point(x, y, z)
  }
  let floor_y = plot.y + plot.height * (1 - (0.0 - low) / (high - low))
  for
    (paint, corners) in [
      (
        self.floor,
        [
          (plot.x, floor_y, 0.0),
          (plot.x, floor_y, projection.depth),
          (plot.x + plot.width, floor_y, projection.depth),
          (plot.x + plot.width, floor_y, 0.0),
        ],
      ),
      (
        self.side,
        [
          (plot.x, plot.y, 0.0),
          (plot.x, floor_y, 0.0),
          (plot.x, floor_y, projection.depth),
          (plot.x, plot.y, projection.depth),
        ],
      ),
      (
        self.back,
        [
          (plot.x, plot.y, projection.depth),
          (plot.x, floor_y, projection.depth),
          (plot.x + plot.width, floor_y, projection.depth),
          (plot.x + plot.width, plot.y, projection.depth),
        ],
      ),
    ] {
    if !paint.0.is_empty() || !paint.1.0.is_empty() {
      out.push(
        bar_polygon(
          corners.map(p => point(p.0, p.1, p.2)),
          if paint.0.is_empty() {
            ""
          } else {
            line_color_effect(paint.0, 0.45, false)
          },
          paint.1,
        ),
      )
    }
  }
  let faces : Array[(Double, Double, @layout.PositionedPrimitive)] = []
  let positives = Array::make(data.categories.length(), 0.0)
  let negatives = Array::make(data.categories.length(), 0.0)
  let slot = (if self.horizontal { plot.height } else { plot.width }) /
    data.categories.length().to_double()
  let depth_slot = projection.depth / data.series.length().to_double()
  for series, values in data.series {
    let (fill, pen) = styles[series]
    for index, value in values.values {
      guard index < data.categories.length() && value is Some(value) else {
        continue
      }
      let start = if self.horizontal {
        if value >= 0 {
          positives[index]
        } else {
          negatives[index]
        }
      } else {
        0.0
      }
      let end = start + value
      if self.horizontal {
        if value >= 0 {
          positives[index] = end
        } else {
          negatives[index] = end
        }
      }
      if fill.is_empty() && pen.0.is_empty() {
        continue
      }
      let (x0, x1, y0, y1) = if self.horizontal {
        let y = plot.y + plot.height - (index.to_double() + 0.5) * slot
        (
          plot.x +
          (start - low).max(0).min(high - low) / (high - low) * plot.width,
          plot.x +
          (end - low).max(0).min(high - low) / (high - low) * plot.width,
          y + slot / 5,
          y - slot / 5,
        )
      } else {
        let x = plot.x + (index.to_double() + 0.5) * slot
        (
          x - slot / 5,
          x + slot / 5,
          plot.y +
          plot.height *
          (1 - (start - low).max(0).min(high - low) / (high - low)),
          plot.y +
          plot.height * (1 - (end - low).max(0).min(high - low) / (high - low)),
        )
      }
      let z0 = (series.to_double() + 0.3) * depth_slot
      let z1 = (series.to_double() + 0.7) * depth_slot
      let points = [
        point(x0, y0, z0),
        point(x0, y0, z1),
        point(x1, y0, z1),
        point(x1, y0, z0),
        point(x0, y1, z0),
        point(x0, y1, z1),
        point(x1, y1, z1),
        point(x1, y1, z0),
      ]
      for
        side, indices in [
          [0, 4, 7, 3],
          [0, 3, 2, 1],
          [0, 1, 5, 4],
          [3, 7, 6, 2],
          [4, 5, 6, 7],
          [1, 2, 6, 5],
        ] {
        let corners = indices.map(i => points[i])
        let area = corners
          .mapi((i, p) => {
            let next = corners[(i + 1) % corners.length()]
            p.0 * next.1 - next.0 * p.1
          })
          .fold(init=0.0, (a, b) => a + b)
        if area * (if end >= start { 1.0 } else { -1.0 }) <= 1.0e-8 {
          continue
        }
        let color = if fill.is_empty() || side == 0 || side == 5 {
          fill
        } else {
          line_color_effect(
            fill,
            if side == 1 || side == 4 {
              0.45
            } else {
              0.35
            },
            false,
          )
        }
        faces.push(
          (
            corners.fold(init=1.0e100, (a, p) => a.min(p.2)),
            corners[0].1,
            bar_polygon(
              if [1, 2, 5].contains(side) {
                [corners[0], corners[3], corners[2], corners[1]]
              } else {
                corners
              },
              color,
              pen,
            ),
          ),
        )
      }
    }
  }
  faces.sort_by((a, b) => {
    let za = if a.0 == b.0 { a.1 } else { a.0 }
    let zb = if a.0 == b.0 { b.1 } else { b.0 }
    if za > zb {
      -1
    } else if za < zb {
      1
    } else {
      0
    }
  })
  out.append(faces.map(face => face.2))
  let draw_axis = fn(
    points : Array[(Double, Double, Double)],
    pen : (String, Double),
  ) {
    out.push(
      line_path(
        points.mapi((i, p) => {
          if i == 0 {
            Move(p.0, p.1)
          } else {
            Line(p.0, p.1)
          }
        }),
        pen,
      ),
    )
  }
  draw_axis(
    [point(plot.x, plot.y, 0), point(plot.x, plot.y + plot.height, 0)],
    if self.horizontal {
      self.category.pen
    } else {
      self.value.pen
    },
  )
  draw_axis(
    [
      point(plot.x, plot.y + plot.height, 0),
      point(plot.x + plot.width, plot.y + plot.height, 0),
    ],
    if self.horizontal {
      self.value.pen
    } else {
      self.category.pen
    },
  )
  let mut value_label_left = 1.0e100
  let mut value_label_right = -1.0e100
  for i, label in labels {
    let ratio = i.to_double() / ticks.to_double()
    let p = if self.horizontal {
      point(plot.x + ratio * plot.width, plot.y + plot.height, 0)
    } else {
      point(plot.x, plot.y + plot.height * (1 - ratio), 0)
    }
    let tick_pen = (
      if self.value.pen.0 == "000000" {
        "868686"
      } else {
        self.value.pen.0
      },
      self.value.pen.1,
    )
    if self.value.major_tick == "out" {
      draw_axis(
        [
          p,
          if self.horizontal {
            point(plot.x + ratio * plot.width, plot.y + plot.height + 3.75, 0)
          } else {
            point(plot.x - 3.75, plot.y + plot.height * (1 - ratio), 0)
          },
        ],
        tick_pen,
      )
    }
    let label_point = if self.horizontal {
      p
    } else {
      point(
        plot.x,
        plot.y +
        plot.height * (1 - ratio) -
        (label.height + 0.1 * 72 / 25.4) / 2,
        0,
      )
    }
    let label_x = if self.horizontal {
      p.0 - label.widths[0] / 2
    } else {
      label_point.0 - value_gap * 1.5 - label.widths[0] - 0.1 * 72 / 25.4
    }
    let label_y = if self.horizontal { p.1 + value_gap } else { label_point.1 }
    value_label_left = value_label_left.min(label_x)
    value_label_right = value_label_right.max(label_x + label.widths[0])
    line_place(out, label, label_x, label_y)
  }
  for i, label in categories {
    let p = if self.horizontal {
      point(plot.x, plot.y + plot.height - (i.to_double() + 0.5) * slot, 0)
    } else {
      point(plot.x + (i.to_double() + 0.5) * slot, plot.y + plot.height, 0)
    }
    line_place(
      out,
      label,
      if self.horizontal {
        p.0 - category_gap * 1.5 - label.widths[0] - 0.1 * 72 / 25.4
      } else {
        p.0 - label.widths[0] / 2
      },
      if self.horizontal {
        p.1 - (label.height + 0.1 * 72 / 25.4) / 2
      } else {
        p.1 + category_gap
      },
    )
  }
  if self.category.major_tick == "out" {
    for i in 0..<=categories.length() {
      let p = if self.horizontal {
        point(plot.x, plot.y + plot.height - i.to_double() * slot, 0)
      } else {
        point(plot.x + i.to_double() * slot, plot.y + plot.height, 0)
      }
      draw_axis(
        [
          p,
          if self.horizontal {
            point(plot.x - 3.75, plot.y + plot.height - i.to_double() * slot, 0)
          } else {
            point(plot.x + i.to_double() * slot, plot.y + plot.height + 3.75, 0)
          },
        ],
        (
          if self.category.pen.0 == "000000" {
            "868686"
          } else {
            self.category.pen.0
          },
          self.category.pen.1,
        ),
      )
    }
  }
  if self.series_axis is Some(axis) {
    if axis.major_tick == "out" {
      for i in 0..<=data.series.length() {
        let p = point(plot.x + plot.width, bottom, i.to_double() * depth_slot)
        draw_axis(
          [p, (p.0 + 3.75, p.1, p.2)],
          (
            if axis.pen.0 == "000000" {
              "868686"
            } else {
              axis.pen.0
            },
            axis.pen.1,
          ),
        )
      }
    }
    for i, series in data.series {
      let label = line_label(series.name, axis.text, probe, profile)
      let p = point(
        plot.x + plot.width,
        plot.y + plot.height,
        (i.to_double() + 0.5) * depth_slot,
      )
      line_place(out, label, p.0 + 10, p.1 - label.height / 2)
    }
    // Native SerAx titles have no automatic position; explicit edge layouts still draw.
    if axis.title is Some(title) && title.position is Some(_) {
      let p = point(
        plot.x + plot.width,
        plot.y + plot.height,
        projection.depth / 2,
      )
      line_caption_place(
        out,
        title,
        p.0,
        p.1 + category_height + category_gap,
        probe,
        profile,
        frame=Some((width, height)),
      )
    }
  }
  // Native 3D geometry starts with 16px margins; the final text pass switches to 17px.
  let text_margin = 17.0 * 0.75
  if self.category.title is Some(title) {
    let title_y = height - text_margin - title_height(Some(title))
    line_caption_place(
      out,
      title,
      point(plot.x + plot.width / 2, title_y, 0).0,
      title_y,
      probe,
      profile,
    )
  }
  if self.value.title is Some(title) {
    let label_width = value_label_right - value_label_left
    let caption_height = line_value_label(
        title.text,
        title.style,
        probe,
        profile,
      ).widths[0] +
      (1 + 2 * 1.016) * 72 / 25.4
    let title_x = if self.perspective == 0 {
      text_margin + 4.4 * 2.88 / 2
    } else {
      point(
        plot.x - label_width,
        plot.y + plot.height / 2 - caption_height / 2,
        0,
      ).0 -
      title_width +
      4.4 * 2.88 / 2
    }
    let title_y = (
        point(plot.x, plot.y, 0).1 + point(plot.x, plot.y + plot.height, 0).1
      ) /
      2 +
      1.44
    line_caption_place(
      out,
      { ..title, rotation: if self.horizontal { 0 } else { -1 }, },
      title_x,
      title_y,
      probe,
      profile,
    )
  }
  if self.legend is Some(legend) {
    let line_height = legend_labels.fold(init=0.0, (a, b) => a.max(b.height))
    let (x, y) = native_legend_position(
      legend.position,
      (width, height),
      (legend_width, line_height * legend_labels.length().to_double()),
      (
        width - text_margin / 2 - legend_width,
        (height - line_height * legend_labels.length().to_double()) / 2,
      ),
    )
    guard line_height * legend_labels.length().to_double() <= height &&
      x + legend_width <= width else {
      @failure.reject(
        "layout-overflow", "Three-dimensional legend exceeds the chart frame",
      )
    }
    if !legend.fill.is_empty() {
      out.push(
        Rectangle({
          x,
          y,
          width: legend_width,
          height: line_height * legend_labels.length().to_double(),
          color: legend.fill,
        }),
      )
    }
    if !legend.pen.0.is_empty() {
      out.push(
        Stroke(
          {
            x,
            y,
            width: legend_width,
            height: line_height * legend_labels.length().to_double(),
          },
          legend.pen.0,
          legend.pen.1,
        ),
      )
    }
    for i, label in legend_labels {
      let top = y + i.to_double() * line_height
      if !styles[i].0.is_empty() {
        out.push(
          Rectangle({
            x: x + legend_gap,
            y: top + (line_height - marker) / 2,
            width: marker,
            height: marker,
            color: styles[i].0,
          }),
        )
      }
      if !styles[i].1.0.is_empty() {
        out.push(
          Stroke(
            {
              x: x + legend_gap,
              y: top + (line_height - marker) / 2,
              width: marker,
              height: marker,
            },
            styles[i].1.0,
            styles[i].1.1,
          ),
        )
      }
      line_place(out, label, x + marker + 2 * legend_gap, top)
    }
  }
  out
}
