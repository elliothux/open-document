///|
fn radar_point(
  index : Int,
  count : Int,
  x : Double,
  y : Double,
  radius : Double,
) -> (Double, Double) {
  let angle = 2.0 * @math.PI * index.to_double() / count.to_double()
  (x + radius * @math.sin(angle), y - radius * @math.cos(angle))
}

///|
fn ChartData::paint_radar(
  self : ChartData,
  width : Double,
  height : Double,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Array[@layout.PositionedPrimitive] raise @failure.Failure {
  let (low, high, step) = self.axis()
  let ticks = ((high - low) / step).round().to_int()
  guard ticks >= 1 && ticks <= 20 else {
    @failure.reject("limit-exceeded", "Chart tick count exceeds limits")
  }
  let count = self.categories.length()
  let x = width / 2
  let y = (height - 20) / 2
  let radius = (width - 120).min(height - 130) / 2
  let pen : @layout.PathStyle = {
    fillAlpha: 1,
    strokeAlpha: 1,
    dash: [],
    cap: 0,
    join: 0,
    miter: 8,
  }
  let out : Array[@layout.PositionedPrimitive] = []
  for tick in 0..<=ticks {
    let r = radius * tick.to_double() / ticks.to_double()
    if tick > 0 && count > 1 {
      let path : Array[@layout.PathSegment] = []
      for index in 0..<count {
        let (px, py) = radar_point(index, count, x, y, r)
        path.push(if index == 0 { Move(px, py) } else { Line(px, py) })
      }
      if count > 2 {
        path.push(Close)
      }
      out.push(Path(path, "", "d9d9d9", 0.5, pen))
    }
    out.append(
      chart_label(
        (low + step * tick.to_double()).to_string(),
        x + 4,
        y - r - 6,
        42,
        16,
        9,
        false,
        probe,
        profile,
      ),
    )
  }
  for index, category in self.categories {
    let (px, py) = radar_point(index, count, x, y, radius)
    out.push(Path([Move(x, y), Line(px, py)], "", "d9d9d9", 0.5, pen))
    let (lx, ly) = radar_point(index, count, x, y, radius + 14)
    out.append(
      chart_label(
        category,
        (lx - 40).max(4).min(width - 84),
        (ly - 8).max(28).min(height - 62),
        80,
        16,
        9,
        true,
        probe,
        profile,
      ),
    )
  }
  for index, series in self.series {
    let points = series.values.mapi((i, value) => {
      value.map(value => {
        radar_point(i, count, x, y, radius * ((value - low) / (high - low)))
      })
    })
    let color = chart_color(index)
    for i, point in points {
      if point is Some((px, py)) {
        if count > 1 &&
          !(count == 2 && i == 1) &&
          points[(i + 1) % count] is Some((nx, ny)) {
          out.push(Path([Move(px, py), Line(nx, ny)], "", color, 1.5, pen))
        }
      }
    }
    for point in points {
      if point is Some((px, py)) {
        out.append(chart_marker(px, py, color))
      }
    }
  }
  out.append(
    chart_label(
      self.label,
      8,
      height - 48,
      width - 16,
      16,
      10,
      true,
      probe,
      profile,
    ),
  )
  out
}
