///|
fn chart_label(
  text : String,
  x : Double,
  y : Double,
  width : Double,
  height : Double,
  size : Double,
  center : Bool,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Array[@layout.PositionedPrimitive] raise @failure.Failure {
  if text.is_empty() || width <= 0 || height <= 0 {
    return []
  }
  let block = probe.text_block(
    text,
    @layout.TextStyle::new("Arial", size, "222222"),
    profile,
    width,
    false,
  )
  let left = if center { x + (width - block.widths[0]).max(0) / 2 } else { x }
  [
    @layout.Clip({ x, y, width, height, }),
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
) -> Array[@layout.PositionedPrimitive] {
  [
    Transform({ a: 1, b: 0, c: 0, d: 1, e: x - 2.5, f: y - 2.5, }),
    Path(shape_path("ellipse", 5, 5, (0, 0, 0)), color, "", 0, {
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
fn DrawingChart::paint(
  self : DrawingChart,
  width : Double,
  height : Double,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Array[@layout.PositionedPrimitive] raise @failure.Failure {
  guard width >= 180 && height >= 150 else {
    @failure.reject(
      "layout-overflow", "Chart frame requires at least 180 x 150 points",
    )
  }
  let data = self.data
  let out : Array[@layout.PositionedPrimitive] = [
    Rectangle({ x: 0, y: 0, width, height, color: "ffffff", }),
    Stroke({ x: 0, y: 0, width, height, }, "d9d9d9", 0.5),
  ]
  out.append(
    chart_label(data.title, 8, 6, width - 16, 20, 12, true, probe, profile),
  )
  if ["pie", "doughnut"].contains(data.kind) {
    out.append(self.paint_pie(width, height, probe, profile))
    return out
  }
  let (low, high, step) = data.axis()
  let horizontal = horizontal_bar_chart(data.kind)
  let stacked = stacked_chart(data.kind)
  let percent = percent_stacked_chart(data.kind)
  let left = if horizontal { 70.0 } else { 44.0 }
  let top = 30.0
  let w = width - left - 12
  let h = height - top - 70
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
  let line = data.kind == "line"
  let area = data.kind == "area"
  let scatter = data.kind == "scatter"
  if scatter {
    out.append(data.paint_scatter(left, top, w, h, probe, profile))
  }
  let slot = if area && slots > 1 {
    w / (slots - 1).to_double()
  } else {
    (if horizontal { h } else { w }) / slots.to_double()
  }
  if area {
    let baseline = top + h * (1 - (0 - low) / (high - low))
    for series_index, series in data.series {
      let path : Array[@layout.PathSegment] = []
      let points : Array[(Double, Double)] = []
      let finish = fn() {
        if points.length() >= 2 {
          path.push(Move(points[0].0, baseline))
          for (x, y) in points {
            path.push(Line(x, y))
          }
          path.push(Line(points[points.length() - 1].0, baseline))
          path.push(Close)
        }
        points.clear()
      }
      for index, value in series.values {
        if value is Some(value) {
          points.push(
            (
              left + (if slots == 1 { w / 2 } else { index.to_double() * slot }),
              top + h * (1 - (value - low) / (high - low)),
            ),
          )
        } else {
          finish()
        }
      }
      finish()
      if !path.is_empty() {
        out.push(
          Path(path, chart_color(series_index), "", 0, {
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
    for series_index, series in data.series {
      let path : Array[@layout.PathSegment] = []
      let markers : Array[@layout.PositionedPrimitive] = []
      let mut connected = false
      for index, value in series.values {
        if value is Some(value) {
          let x = left + (index.to_double() + 0.5) * slot
          let y = top + h * (1 - (value - low) / (high - low))
          path.push(if connected { Line(x, y) } else { Move(x, y) })
          markers.append(chart_marker(x, y, chart_color(series_index)))
          connected = true
        } else {
          connected = false
        }
      }
      if path.any(segment => segment is Line(_, _)) {
        out.push(
          Path(path, "", chart_color(series_index), 1.5, {
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
          let rect : @layout.Fill = if horizontal {
            {
              x: left + w * baseline.min(ratio),
              y: top + offset,
              width: w * (ratio - baseline).abs(),
              height: bar,
              color: chart_color(series_index),
            }
          } else {
            {
              x: left + offset,
              y: top + h * (1 - baseline.max(ratio)),
              width: bar,
              height: h * (ratio - baseline).abs(),
              color: chart_color(series_index),
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
  let legend_width = (width - 16) / data.series.length().to_double()
  for i, series in data.series {
    let x = 8.0 + legend_width * i.to_double()
    if scatter {
      out.append(chart_marker(x + 4, height - 14, chart_color(i)))
    } else if line {
      out.push(
        Path(
          [Move(x, height - 14), Line(x + 8, height - 14)],
          "",
          chart_color(i),
          1.5,
          { fillAlpha: 1, strokeAlpha: 1, dash: [], cap: 0, join: 0, miter: 8, },
        ),
      )
      out.append(chart_marker(x + 4, height - 14, chart_color(i)))
    } else {
      out.push(
        Rectangle({
          x,
          y: height - 18,
          width: 8,
          height: 8,
          color: chart_color(i),
        }),
      )
    }
    out.append(
      chart_label(
        series.name,
        x + 12,
        height - 21,
        legend_width - 16,
        18,
        10,
        false,
        probe,
        profile,
      ),
    )
  }
  out
}
