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
  let (low, high, step) = data.axis()
  let horizontal = data.kind == "bar"
  let left = if horizontal { 70.0 } else { 44.0 }
  let top = 30.0
  let w = width - left - 12
  let h = height - top - 70
  let out : Array[@layout.PositionedPrimitive] = [
    Rectangle({ x: 0, y: 0, width, height, color: "ffffff", }),
    Stroke({ x: 0, y: 0, width, height, }, "d9d9d9", 0.5),
  ]
  out.append(
    chart_label(data.title, 8, 6, width - 16, 20, 12, true, probe, profile),
  )
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
        value.to_string(),
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
  let slot = (if horizontal { h } else { w }) / slots.to_double()
  let bar = slot / (data.series.length().to_double() + 1.5)
  let zero = (0.0 - low) / (high - low)
  let stride = ((if horizontal { 14.0 } else { 48.0 }) / slot)
    .ceil()
    .to_int()
    .max(1)
  for index, category in data.categories {
    let position = if horizontal { slots - 1 - index } else { index }
    let at = position.to_double() * slot
    if index % stride == 0 {
      out.append(
        chart_label(
          category,
          if horizontal {
            4
          } else {
            left + at
          },
          if horizontal {
            top + at + (slot - 14) / 2
          } else {
            top + h + 4
          },
          if horizontal {
            left - 8
          } else {
            slot
          },
          16,
          10,
          !horizontal,
          probe,
          profile,
        ),
      )
    }
    for series_index, series in data.series {
      if series.values[index] is Some(value) {
        let ratio = (value - low) / (high - low)
        let offset = at + bar * (0.75 + series_index.to_double())
        let rect : @layout.Fill = if horizontal {
          {
            x: left + w * zero.min(ratio),
            y: top + offset,
            width: w * (ratio - zero).abs(),
            height: bar,
            color: chart_color(series_index),
          }
        } else {
          {
            x: left + offset,
            y: top + h * (1 - zero.max(ratio)),
            width: bar,
            height: h * (ratio - zero).abs(),
            color: chart_color(series_index),
          }
        }
        if rect.width > 0 && rect.height > 0 {
          out.push(Rectangle(rect))
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
    out.push(
      Rectangle({
        x,
        y: height - 18,
        width: 8,
        height: 8,
        color: chart_color(i),
      }),
    )
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
