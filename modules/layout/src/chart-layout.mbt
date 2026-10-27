///|
fn chart_label(
  text : String,
  x : Double,
  y : Double,
  width : Double,
  height : Double,
  size : Double,
  center : Bool,
  probe : TextProbe,
  profile : Map[String, String],
) -> Array[PositionedPrimitive] raise @failure.Failure {
  if text.is_empty() || width <= 0 || height <= 0 {
    return []
  }
  let block = probe.text_block(
    text,
    TextStyle::new("Arial", size, "222222"),
    profile,
    width,
    false,
  )
  let left = if center { x + (width - block.widths[0]).max(0) / 2 } else { x }
  [
    Clip({ x, y, width, height, }),
    Transform({ a: 1, b: 0, c: 0, d: 1, e: left, f: y, }),
    ..block.lines.flatten(),
    Restore,
    Restore,
  ]
}

///|
fn chart_marker(
  x : Double,
  y : Double,
  color : String,
) -> Array[PositionedPrimitive] {
  [
    Transform({ a: 1, b: 0, c: 0, d: 1, e: x - 2.5, f: y - 2.5, }),
    Path(basic_shape_path("ellipse", 5, 5), color, "", 0, {
      fillAlpha: 1,
      strokeAlpha: 1,
      dash: [],
      cap: 0,
      join: 0,
      miter: 8,
    }),
    Restore,
  ]
}

///|
fn ChartData::paint_plot(
  self : ChartData,
  width : Double,
  height : Double,
  probe : TextProbe,
  profile : Map[String, String],
  colors : Array[String],
) -> Array[PositionedPrimitive] raise @failure.Failure {
  let data = self
  let out : Array[PositionedPrimitive] = []
  if ["pie", "doughnut"].contains(data.kind) {
    return self.paint_pie(width, height, colors)
  }
  if data.kind == "radar" {
    // The radar plot already reserves 22 points below its axis label.
    return data.paint_radar_colors(width, height + 22, probe, profile, colors)
  }
  let (low, high, step) = data.axis()
  let horizontal = horizontal_bar_chart(data.kind)
  let stacked = stacked_chart(data.kind)
  let percent = percent_stacked_chart(data.kind)
  let left = if horizontal { 70.0 } else { 44.0 }
  let top = 30.0
  let w = width - left - 12
  let h = height - top - 48
  let ticks = ((high - low) / step).round().to_int()
  guard ticks >= 1 && ticks <= 20 else {
    @failure.reject("limit-exceeded", "Chart tick count exceeds limits")
  }
  for i in 0..<=ticks {
    let value = low + step * i.to_double()
    let ratio = (value - low) / (high - low)
    let (x, y) = if horizontal {
      (left + w * ratio, top)
    } else {
      (left, top + h * (1 - ratio))
    }
    out.push(
      Path(
        if horizontal {
          [Move(x, y), Line(x, y + h)]
        } else {
          [Move(x, y), Line(x + w, y)]
        },
        "",
        "d9d9d9",
        0.5,
        { fillAlpha: 1, strokeAlpha: 1, dash: [], cap: 0, join: 0, miter: 8, },
      ),
    )
    out.append(
      chart_label(
        if percent {
          (value * 100).round().to_int().to_string() + "%"
        } else {
          value.to_string()
        },
        if horizontal {
          x - 22
        } else {
          0
        },
        if horizontal {
          top + h + 4
        } else {
          y - 6
        },
        if horizontal {
          44
        } else {
          left - 5
        },
        16,
        9,
        horizontal,
        probe,
        profile,
      ),
    )
  }
  let slots = data.categories.length()
  let line = line_chart(data.kind)
  let area = area_chart(data.kind)
  let scatter = data.kind == "scatter"
  if scatter {
    out.append(data.paint_scatter(left, top, w, h, probe, profile, colors))
  }
  let slot = if area && slots > 1 {
    w / (slots - 1).to_double()
  } else {
    (if horizontal { h } else { w }) / slots.to_double()
  }
  if area {
    let baseline = top + h * (1 - (0 - low) / (high - low))
    let cumulative = Array::make(slots, 0.0)
    for series_index, series in data.series {
      let path : Array[PathSegment] = []
      let points : Array[(Double, Double, Double)] = []
      let finish = fn() {
        if points.length() >= 2 {
          path.push(Move(points[0].0, points[0].2))
          for (x, y, _) in points {
            path.push(Line(x, y))
          }
          if stacked {
            for index = points.length() - 1; index >= 0; index = index - 1 {
              path.push(Line(points[index].0, points[index].2))
            }
          } else {
            path.push(Line(points[points.length() - 1].0, baseline))
          }
          path.push(Close)
        }
        points.clear()
      }
      for index, value in series.values {
        let value = if stacked {
          Some(data.bar_values(index)[series_index].unwrap_or(0))
        } else {
          value
        }
        if value is Some(value) {
          let start = cumulative[index]
          let end = if percent {
            (start + value).clamp(min=-1, max=1)
          } else {
            start + value
          }
          if stacked {
            cumulative[index] = end
          }
          points.push(
            (
              left + (if slots == 1 { w / 2 } else { index.to_double() * slot }),
              top + h * (1 - (end - low) / (high - low)),
              if stacked {
                top + h * (1 - (start - low) / (high - low))
              } else {
                baseline
              },
            ),
          )
        } else {
          finish()
        }
      }
      finish()
      if !path.is_empty() {
        out.push(
          Path(path, chart_paint_color(colors, series_index), "", 0, {
            fillAlpha: 1,
            strokeAlpha: 1,
            dash: [],
            cap: 0,
            join: 0,
            miter: 8,
          }),
        )
      }
    }
  }
  if line {
    let cumulative = Array::make(slots, 0.0)
    for series_index, series in data.series {
      let path : Array[PathSegment] = []
      let markers : Array[PositionedPrimitive] = []
      let mut connected = false
      for index, value in series.values {
        let value = if stacked {
          // Native stacked lines treat missing points as zero contributions.
          let next = cumulative[index] +
            data.bar_values(index)[series_index].unwrap_or(0)
          cumulative[index] = if percent {
            next.clamp(min=-1, max=1)
          } else {
            next
          }
          Some(cumulative[index])
        } else {
          value
        }
        if value is Some(value) {
          let x = left + (index.to_double() + 0.5) * slot
          let y = top + h * (1 - (value - low) / (high - low))
          path.push(if connected { Line(x, y) } else { Move(x, y) })
          markers.append(
            chart_marker(x, y, chart_paint_color(colors, series_index)),
          )
          connected = true
        } else {
          connected = false
        }
      }
      if path.any(segment => segment is Line(_, _)) {
        out.push(
          Path(path, "", chart_paint_color(colors, series_index), 1.5, {
            fillAlpha: 1,
            strokeAlpha: 1,
            dash: [],
            cap: 0,
            join: 0,
            miter: 8,
          }),
        )
      }
      out.append(markers)
    }
  }
  let bar = slot /
    ((if stacked { 1 } else { data.series.length() }).to_double() + 1.5)
  let zero = (0.0 - low) / (high - low)
  let stride = ((if horizontal { 14.0 } else { 48.0 }) / slot)
    .ceil()
    .to_int()
    .max(1)
  if !scatter {
    for index, category in data.categories {
      let position = if horizontal { slots - 1 - index } else { index }
      let at = position.to_double() * slot
      let (label_x, label_width) = if area {
        let center = left + (if slots == 1 { w / 2 } else { at })
        let first = (center - slot / 2).max(0)
        (first, (center + slot / 2).min(width) - first)
      } else {
        (left + at, slot)
      }
      if index % stride == 0 {
        out.append(
          chart_label(
            category,
            if horizontal {
              4
            } else {
              label_x
            },
            if horizontal {
              top + at + (slot - 14) / 2
            } else {
              top + h + 4
            },
            if horizontal {
              left - 8
            } else {
              label_width
            },
            16,
            10,
            !horizontal,
            probe,
            profile,
          ),
        )
      }
      if line || area {
        continue
      }
      let mut positive = 0.0
      let mut negative = 0.0
      for series_index, value in data.bar_values(index) {
        if value is Some(value) {
          let start = if !stacked {
            0.0
          } else if value >= 0 {
            positive
          } else {
            negative
          }
          let end = if percent {
            (start + value).clamp(min=-1, max=1)
          } else {
            start + value
          }
          if stacked {
            if value >= 0 {
              positive = end
            } else {
              negative = end
            }
          }
          let baseline = if stacked {
            (start - low) / (high - low)
          } else {
            zero
          }
          let ratio = (end - low) / (high - low)
          let offset = at +
            bar *
            (0.75 + (if stacked { 0.0 } else { series_index.to_double() }))
          let rect : Fill = if horizontal {
            {
              x: left + w * baseline.min(ratio),
              y: top + offset,
              width: w * (ratio - baseline).abs(),
              height: bar,
              color: chart_paint_color(colors, series_index),
            }
          } else {
            {
              x: left + offset,
              y: top + h * (1 - baseline.max(ratio)),
              width: bar,
              height: h * (ratio - baseline).abs(),
              color: chart_paint_color(colors, series_index),
            }
          }
          if rect.width > 0 && rect.height > 0 {
            out.push(Rectangle(rect))
          }
        }
      }
    }
  }
  out.append(
    chart_label(data.label, left, top + h + 21, w, 16, 10, true, probe, profile),
  )
  out
}
