///|
fn NativeLine::paint(
  self : NativeLine,
  source : @layout.ChartData,
  width : Double,
  height : Double,
  probe : @layout.TextProbe,
  profile : Map[String, String],
  visible : @layout.ChartVisibility?,
  after_bar3d : Bool,
  print : Bool,
) -> Array[@layout.PositionedPrimitive] raise @failure.Failure {
  source.validate_sources()
  guard width >= 180 && width <= 14400 && height >= 150 && height <= 14400 else {
    @failure.reject(
      "layout-overflow", "Native line frame requires at least 180 x 150 points",
    )
  }
  let scatter = source.kind == "scatter"
  let mixed = self.series.any(curve => curve.column is Some(_))
  let (data, styles) = native_visible(self.series, source, visible)
  let styles = if visible is Some(visibility) {
    let values = visibility.values.filter(indices => !indices.is_empty())
    styles.mapi((index, curve) => {
      let points : Map[Int32, NativeLineSeries] = Map([])
      for at, original in values[index] {
        if curve.points.get(original) is Some(paint) {
          points[at] = paint
        }
      }
      let column = curve.column.map(column => {
        let points : Map[Int32, (String, (String, Double))] = Map([])
        for at, original in values[index] {
          if column.points.get(original) is Some(paint) {
            points[at] = paint
          }
        }
        { ..column, points, }
      })
      { ..curve, points, column, }
    })
  } else {
    styles
  }
  let axis_labels : Array[@layout.PositionedPrimitive] = []
  let out : Array[@layout.PositionedPrimitive] = [
    Rectangle({ x: 0, y: 0, width, height, color: self.frame_fill, }),
    line_path(
      if self.frame_dash.is_empty() {
        [
          Move(0, 0),
          Line(width, 0),
          Line(width, height),
          Line(0, height),
          Close,
        ]
      } else {
        [
          Move(0, 0),
          Line(0, height),
          Line(width, height),
          Line(width, 0),
          Line(0, 0),
        ]
      },
      self.frame_pen,
      dash=self.frame_dash,
    ),
  ]
  if data.categories.is_empty() || data.series.is_empty() {
    return out
  }
  let axis_strokes : Array[@layout.PositionedPrimitive] = if mixed {
    []
  } else {
    out
  }
  let ranges = self.axes.mapi((axis, style) => {
    line_axis_range(style, {
      ..data,
      series: data.series
      .mapi((i, series) => {
        if styles[i].axis == axis {
          Some(series)
        } else {
          None
        }
      })
      .filter_map(value => value),
    })
  })
  let (low, high, step) = ranges[0]
  let xs = if scatter {
    data.categories.map(text => {
      if text.is_empty() {
        None
      } else {
        Some(
          @string.parse_double(text) catch {
            _ =>
              @failure.reject("invalid-chart", "Invalid scatter X coordinate")
          },
        )
      }
    })
  } else {
    []
  }
  let x_ranges = if scatter {
    self.axes.mapi((axis, _) => {
      line_axis_range(
        if axis == 0 {
          self.category
        } else {
          self.secondary_x.unwrap()
        },
        { ..data, series: [{ name: "", values: xs, }], },
      )
    })
  } else {
    []
  }
  let trends = data.series.mapi((i, series) => {
    if series.values.filter_map(value => value).length() < 2 {
      None
    } else {
      styles[i].trend.map(trend => line_polynomial(series.values, trend.order))
    }
  })
  let ticks = ((high - low) / step).round().to_int()
  guard ticks > 0 && ticks <= 600 else {
    @failure.reject("limit-exceeded", "Native line tick count exceeds budget")
  }
  let value_labels = Array::makei(ticks + 1, i => {
    line_value_label(
      line_tick(low + i.to_double() * step).to_string(),
      self.axes[0].text,
      probe,
      profile,
    )
  })
  let secondary_labels = if self.axes.length() == 2 {
    let (lo, hi, interval) = ranges[1]
    Array::makei(((hi - lo) / interval).round().to_int() + 1, i => {
      line_value_label(
        line_tick(lo + i.to_double() * interval).to_string(),
        self.axes[1].text,
        probe,
        profile,
      )
    })
  } else {
    []
  }
  let category_labels = if scatter {
    let (lo, hi, step) = x_ranges[0]
    Array::makei(((hi - lo) / step).round().to_int() + 1, i => {
      line_value_label(
        line_tick(lo + i.to_double() * step).to_string(),
        self.category.text,
        probe,
        profile,
      )
    })
  } else {
    data.categories.map(text => {
      let text = if self.numeric_categories && !text.is_empty() {
        let value = @string.parse_double(text) catch {
          _ =>
            @failure.reject("invalid-chart", "Invalid native numeric category")
        }
        if value == 0 {
          "0"
        } else {
          value.to_string()
        }
      } else {
        text
      }
      line_label(text, self.category.text, probe, profile)
    })
  }
  let label_width = value_labels.fold(init=0.0, (width, block) => {
      width.max(block.widths[0])
    }) +
    0.1 * 72 / 25.4
  let label_height = value_labels.fold(init=0.0, (height, block) => {
      height.max(block.height)
    }) +
    0.1 * 72 / 25.4
  let category_height = category_labels.fold(init=0.0, (height, block) => {
    height.max(block.height)
  })
  let axis_title_margin = (if after_bar3d { 17.0 } else { 14.0 }) * 0.75
  let margin = axis_title_margin
  let value_gap = line_offset(self.axes[0].text, probe, profile) * 1.5
  let category_gap = line_offset(self.category.text, probe, profile)
  let category_ratio = 1.0 - ((0.0 - low) / (high - low)).max(0).min(1)
  let top = label_height / 2 + margin / 3
  let available = height - top - margin * 2 / 3
  let plot_height = (available - label_height / 2).min(
    if category_ratio > 0 {
      (available - category_height - category_gap) / category_ratio
    } else {
      available
    },
  )
  let legend = self.layout_legend(
    data,
    styles,
    visible,
    (width, height),
    plot_height,
    probe,
    profile,
  )
  let legend_width = legend.width
  let point_legend_bottom = self.point_legend && self.legend_bottom
  let right = secondary_labels.fold(init=0.0, (width, block) => {
      width.max(block.widths[0])
    }) +
    (if secondary_labels.is_empty() {
      0.0
    } else {
      line_offset(self.axes[1].text, probe, profile) * 1.5 + 0.1 * 72 / 25.4
    })
  let plot : @layout.Border = if self.plot is Some(rect) {
    {
      x: rect.x * width + label_width + value_gap,
      y: rect.y * height + label_height / 2,
      width: rect.width * width - label_width - value_gap - right,
      height: rect.height * height -
      label_height / 2 -
      category_height -
      category_gap,
    }
  } else {
    {
      x: label_width + value_gap + margin / 2,
      y: top,
      width: width -
      label_width -
      value_gap -
      margin / 2 -
      (if point_legend_bottom { 0.0 } else { legend_width }) -
      (if mixed {
        right + margin * 2 / 3
      } else if scatter {
        // Numeric end labels extend past the final tick in the native axes layout.
        category_labels.last().unwrap().widths[0] / 2 +
        margin * (if legend_width == 0 { 1.0 } else { 5.0 / 3 })
      } else {
        margin * 5 / 3
      }),
      height: plot_height -
      (if point_legend_bottom { legend.height } else { 0.0 }),
    }
  }
  let background : @layout.Border = {
    x: plot.x - 0.75,
    y: plot.y - 0.75,
    width: plot.width + 0.75,
    height: plot.height + 0.75,
  }
  guard plot.width > 12 && plot.height > 12 else {
    @failure.reject(
      "layout-overflow", "Native line labels exceed the chart frame",
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
  if !self.plot_pen.0.is_empty() {
    out.push(Stroke(background, self.plot_pen.0, self.plot_pen.1))
  }
  let slot = plot.width / data.categories.length().to_double()
  let has_x = fn(index : Int32) {
    !scatter || xs.get(index).bind(value => value) is Some(_)
  }
  let x_at = fn(index : Int32, axis : Int32) {
    if scatter {
      let (lo, hi, _) = x_ranges[axis]
      plot.x + (xs[index].unwrap() - lo) / (hi - lo) * plot.width
    } else {
      plot.x + (index.to_double() + 0.5) * slot
    }
  }
  // Native axes cover the category grid at their intersections.
  if !self.category.major.0.is_empty() {
    let count = if scatter {
      category_labels.length() - 1
    } else {
      data.categories.length()
    }
    for i in 0..<=count {
      let x = if scatter {
        plot.x + i.to_double() / count.to_double() * plot.width
      } else {
        plot.x + i.to_double() * slot
      }
      out.push(
        line_path(
          [Move(x, plot.y), Line(x, plot.y + plot.height)],
          self.category.major,
        ),
      )
    }
  }
  let primary_ticks : Array[@layout.PathSegment] = []
  for i, label in value_labels {
    let y = plot.y + plot.height * (1 - i.to_double() / ticks.to_double())
    if !self.axes[0].major.0.is_empty() {
      out.push(
        line_path(
          [Move(plot.x, y), Line(plot.x + plot.width, y)],
          (
            if self.axes[0].major.0 == "000000" {
              "868686"
            } else {
              self.axes[0].major.0
            },
            self.axes[0].major.1,
          ),
        ),
      )
    }
    line_axis_tick(
      primary_ticks,
      plot.x,
      y,
      self.axes[0].pen,
      self.axes[0].major_tick,
      false,
    )
    line_place(
      axis_labels,
      label,
      plot.x - value_gap - label.widths[0] - 0.1 * 72 / 25.4,
      y - (label.height + 0.1 * 72 / 25.4) / 2,
    )
  }
  line_minor_grid(out, primary_ticks, plot, self.axes[0], ticks, false)
  if !primary_ticks.is_empty() {
    let pen = self.axes[0].pen
    axis_strokes.push(
      line_path(
        primary_ticks,
        (if pen.0 == "000000" { "868686" } else { pen.0 }, pen.1),
      ),
    )
  }
  if self.axes.length() == 2 {
    let style = self.axes[1]
    let x = plot.x + plot.width
    let ticks = secondary_labels.length() - 1
    let tick_paths : Array[@layout.PathSegment] = []
    for i, label in secondary_labels {
      let y = plot.y + plot.height * (1 - i.to_double() / ticks.to_double())
      line_axis_tick(tick_paths, x, y, style.pen, style.major_tick, true)
      line_place(
        axis_labels,
        label,
        x + line_offset(style.text, probe, profile) * 1.5,
        y - (label.height + 0.1 * 72 / 25.4) / 2,
      )
    }
    line_minor_grid(out, tick_paths, plot, style, ticks, true)
    axis_strokes.push(
      line_path([Move(x, plot.y), Line(x, plot.y + plot.height)], style.pen),
    )
    // Native axes stroke their major and minor ticks together, including shared endpoints.
    if !tick_paths.is_empty() {
      axis_strokes.push(
        line_path(
          tick_paths,
          (
            if style.pen.0 == "000000" {
              "868686"
            } else {
              style.pen.0
            },
            style.pen.1,
          ),
        ),
      )
    }
  }
  axis_strokes.push(
    line_path(
      [Move(plot.x, plot.y), Line(plot.x, plot.y + plot.height)],
      self.axes[0].pen,
    ),
  )
  let category_y = plot.y + category_ratio * plot.height
  axis_strokes.push(
    line_path(
      [Move(plot.x, category_y), Line(plot.x + plot.width, category_y)],
      self.category.pen,
    ),
  )
  let count = if scatter {
    category_labels.length() - 1
  } else {
    data.categories.length()
  }
  for i in 0..<=count {
    let x = if scatter {
      plot.x + i.to_double() / count.to_double() * plot.width
    } else {
      plot.x + i.to_double() * slot
    }
    if self.category.major_tick != "none" {
      axis_strokes.push(
        line_path(
          [Move(x, category_y), Line(x, category_y + 3.75)],
          (
            if self.category.pen.0 == "000000" {
              "868686"
            } else {
              self.category.pen.0
            },
            self.category.pen.1,
          ),
        ),
      )
    }
  }
  let maximum = category_labels.fold(init=0.0, (width, block) => {
    width.max(block.widths[0])
  })
  let skip = ((maximum + 2) /
    (if scatter { plot.width / count.to_double() } else { slot }))
    .ceil()
    .to_int()
    .max(1)
  for i, label in category_labels {
    if i % skip == 0 {
      let x = if scatter {
        plot.x + i.to_double() / count.to_double() * plot.width
      } else {
        x_at(i, 0)
      }
      line_place(
        axis_labels,
        label,
        x - label.widths[0] / 2,
        category_y + category_gap,
      )
    }
  }
  if mixed {
    if print {
      out.push(Clip({ ..background, width: plot.width, height: plot.height, }))
    }
    line_columns(out, data, styles, ranges, plot)
    if print {
      out.push(Restore)
    }
    out.append(axis_strokes)
  }
  for axis in 0..<self.axes.length() {
    out.push(Clip({ ..plot, y: plot.y - 2.25, height: plot.height + 2.25, }))
    let (low, high, _) = ranges[axis]
    for index, series in data.series {
      let curve = styles[index]
      if curve.axis != axis || curve.column is Some(_) {
        continue
      }
      let style = curve.paint
      let mut points : Array[(Double, Double)] = []
      let mut indices : Array[Int32] = []
      let flush = fn(points : Array[(Double, Double)], indices : Array[Int32]) {
        let units = (
          if scatter {
            plot.width / (x_ranges[axis].1 - x_ranges[axis].0)
          } else {
            slot
          },
          plot.height / (high - low),
        )
        let paths = if !curve.smooth {
          points
          .mapi((i, _) => {
            if i == 0 {
              []
            } else {
              line_curve_paths([points[i - 1], points[i]], false, units, plot)
            }
          })
          .flatten()
        } else {
          line_curve_paths(points, curve.smooth, units, plot)
        }
        for segment, path in paths {
          if path.is_empty() {
            continue
          }
          let style = if scatter {
            curve.points.get(indices[segment + 1]).unwrap_or(style)
          } else {
            style
          }
          out.push(line_path(path, (style.color, style.width), dash=curve.dash))
        }
      }
      for i, value in series.values {
        if value is Some(value) && has_x(i) {
          points.push(
            (
              x_at(i, axis),
              plot.y + plot.height * (1.0 - (value - low) / (high - low)),
            ),
          )
          indices.push(i)
        } else {
          flush(points, indices)
          points = []
          indices = []
        }
      }
      flush(points, indices)
    }
    out.push(Restore)
    // Native line groups paint all markers after their strokes, without the plot clip.
    let mut marker_paint : NativeLineSeries? = None
    for index, series in data.series {
      // Native numeric-X scatter has no series marker for a point-color palette.
      if styles[index].axis != axis ||
        styles[index].column is Some(_) ||
        !styles[index].plot_markers {
        continue
      }
      let mut cache_at = 0
      let mut previous_y : Int32? = None
      for i, value in series.values {
        if value is Some(value) {
          if scatter {
            if previous_y is Some(previous) {
              cache_at += i - previous - 1
            }
            previous_y = Some(i)
          }
          if !has_x(i) {
            continue
          }
          let x = x_at(i, axis)
          if scatter &&
            (
              x < plot.x ||
              x > plot.x + plot.width ||
              value < low ||
              value > high
            ) {
            continue
          }
          let shape = styles[index].points.get(i).unwrap_or(styles[index].paint)
          let marker = if scatter {
            // Native paths use packed cache positions; absent entries retain the last brush and pen.
            if series.values.get(cache_at) is Some(Some(_)) {
              marker_paint = if styles[index].paint.marker == "none" &&
                styles[index].points.is_empty() {
                None
              } else {
                Some(
                  styles[index].points
                  .get(cache_at)
                  .unwrap_or(styles[index].paint),
                )
              }
            }
            cache_at += 1
            marker_paint
            .map(paint => {
              ..shape,
              marker_fill: paint.marker_fill,
              marker_pen: paint.marker_pen,
            })
            .unwrap_or({ ..shape, marker: "none", })
          } else {
            shape
          }
          marker.marker_at(
            out,
            x,
            plot.y +
            plot.height * (1.0 - (value - low) / (high - low)).max(0).min(1),
            open_diamond=scatter,
          )
        }
      }
    }
  }
  out.push(Clip(plot))
  for index, _ in data.series {
    let curve = styles[index]
    let (low, high, _) = ranges[curve.axis]
    if curve.trend is Some(trend) && trends[index] is Some(fit) {
      let path = Array::makei(101, i => {
        let cat = 1.0 +
          (i - 1).max(0).to_double() /
          99 *
          (data.categories.length() - 1).to_double()
        let x = plot.x + (cat - 0.5) * slot
        let y = plot.y +
          plot.height * (1 - (fit.value(cat) - low) / (high - low))
        if i == 0 {
          @layout.Move(x, y)
        } else {
          @layout.Line(x, y)
        }
      })
      out.push(line_path(path, trend.pen, dash=trend.dash))
    }
  }
  out.push(Restore)
  for index, series in data.series {
    let curve = styles[index]
    let (low, high, _) = ranges[curve.axis]
    if curve.labels is Some(labels) {
      for i, value in series.values {
        if value is Some(value) {
          let text = (if labels.series { series.name } else { "" }) +
            (if labels.series && labels.value { ", " } else { "" }) +
            (if labels.value { line_general(value) } else { "" })
          if text.is_empty() {
            continue
          }
          let block = line_value_label(text, labels.text, probe, profile)
          let max_width = (width / 5 - 2 * 2.88).clamp(min=1, max=14400)
          let block = if block.widths[0] > max_width {
            line_centered_block(
              probe.text_block(text, labels.text, profile, max_width, true),
            )
          } else {
            block
          }
          let padding = 2.88 + 0.5 * 72 / 25.4
          let box_width = block.widths.fold(init=0.0, (a, b) => a.max(b)) +
            2.25 * 72 / 25.4
          let vertical = 1.44
          let x = (plot.x + (i.to_double() + 0.5) * slot + 3.75)
            .min(width - box_width)
            .max(0)
          let y = plot.y +
            plot.height * (1.0 - (value - low) / (high - low)).max(0).min(1) -
            block.height / 2 -
            vertical
          let bounds : @layout.Border = {
            x,
            y,
            width: box_width,
            height: block.height + vertical * 2,
          }
          if !labels.fill.is_empty() {
            out.push(
              Rectangle({
                x,
                y,
                width: bounds.width,
                height: bounds.height,
                color: labels.fill,
              }),
            )
          }
          if !labels.pen.0.is_empty() {
            out.push(Stroke(bounds, labels.pen.0, labels.pen.1))
          }
          line_place(out, block, x + padding, y + vertical)
        }
      }
    }
    if curve.trend is Some(trend) &&
      trends[index] is Some(fit) &&
      (trend.equation || trend.r_squared) {
      let block = line_trend_text(trend, fit, width, probe, profile)
      let box_width = block.widths.fold(init=0.0, (maximum, value) => {
          maximum.max(value)
        }) +
        2.25 * 72 / 25.4
      let x = (plot.x + plot.width - slot / 2 - box_width).max(0) +
        2.88 +
        0.5 * 72 / 25.4
      let y = (plot.y +
      plot.height *
      (
        1 -
        (fit.value(data.categories.length().to_double()) - low) / (high - low)
      )).max(plot.y)
      let y = (y - block.height / 2).max(0).min(height - block.height)
      line_place(out, block, x, y)
    }
  }
  if self.title is Some(title) {
    line_caption_place(out, title, width / 2, 7 * 0.75, probe, profile)
  }
  if self.category.title is Some(title) {
    line_caption_place(
      out,
      title,
      plot.x + plot.width / 2,
      self.plot
      .map(rect => {
        (rect.y + rect.height) * height + category_gap + category_height
      })
      .unwrap_or(plot.y + plot.height + category_gap + category_height),
      probe,
      profile,
    )
  }
  if scatter && self.secondary_x.bind(axis => axis.title) is Some(title) {
    line_caption_place(
      out,
      title,
      plot.x + plot.width / 2,
      plot.y + plot.height + category_gap + category_height,
      probe,
      profile,
    )
  }
  if self.axes[0].title is Some(title) {
    line_caption_place(
      out,
      title,
      axis_title_margin + 4.4 * 2.88 / 2,
      plot.y + plot.height / 2 + 1.44,
      probe,
      profile,
    )
  }
  if scatter && self.axes.get(1).bind(axis => axis.title) is Some(title) {
    line_caption_place(
      out,
      title,
      width -
      axis_title_margin -
      legend_width -
      line_value_label(title.text, title.style, probe, profile).height -
      4.4 * 2.88 / 2,
      plot.y + plot.height / 2 + 1.44,
      probe,
      profile,
    )
  }
  // Native charts paint axis text after series labels, so labels cannot erase tick text.
  out.append(axis_labels)
  let fallback = if point_legend_bottom {
    ((width - legend_width) / 2, height - legend.height - margin / 2)
  } else {
    (
      width - legend_width - margin / 2,
      (height - legend.row_height * legend.labels.length().to_double()) / 2,
    )
  }
  let (x, y) = native_legend_position(
    self.legend_position,
    (width, height),
    (legend_width, legend.height),
    fallback,
  )
  self.paint_legend(
    out,
    { x, y, width: legend_width, height: legend.height, },
    legend,
    probe,
  )
  out
}
