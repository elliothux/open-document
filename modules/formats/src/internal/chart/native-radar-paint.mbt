///|
fn radar_path(
  path : Array[@layout.PathSegment],
  pen : (String, Double),
  fill~ : String = "",
  dash~ : Array[Double] = [],
  join~ : Int32 = 0,
) -> @layout.PositionedPrimitive {
  @layout.Path(path, fill, pen.0, pen.1, {
    evenOdd: false,
    fillAlpha: 1,
    strokeAlpha: 1,
    dash,
    cap: 0,
    join,
    miter: 10,
  })
}

///|
fn NativeRadar::paint(
  self : NativeRadar,
  source : @layout.ChartData,
  width : Double,
  height : Double,
  visible : @layout.ChartVisibility?,
) -> Array[@layout.PositionedPrimitive] raise @failure.Failure {
  source.validate_sources()
  guard !width.is_nan() &&
    !height.is_nan() &&
    width > 0 &&
    width <= 14400 &&
    height > 0 &&
    height <= 14400 else {
    @failure.reject("layout-overflow", "Native radar frame exceeds limits")
  }
  let (data, styles) = native_visible(self.series, source, visible)
  let out : Array[@layout.PositionedPrimitive] = [
    Rectangle({ x: 0, y: 0, width, height, color: self.frame_fill, }),
    radar_path(
      @layout.basic_shape_path("rect", width, height),
      self.frame_pen,
      join=self.frame_join,
    ),
  ]
  if data.categories.is_empty() || data.series.is_empty() {
    return out
  }
  let (low, high, step) = line_scale(data, radar=true)
  let ticks = ((high - low) / step).round().to_int()
  guard ticks > 0 && ticks <= 600 else {
    @failure.reject("limit-exceeded", "Native radar ticks exceed limits")
  }
  let plot = self.plot.unwrap_or({ x: 0, y: 0, width: 1, height: 1, })
  let center_x = width * (plot.x + plot.width / 2)
  let center_y = height * (plot.y + plot.height / 2)
  let radius = (width * plot.width).min(height * plot.height) / 2
  let count = data.categories.length()
  let angle = (if self.reversed { -2.0 } else { 2.0 }) *
    @math.PI /
    count.to_double()
  let point = (index : Int32, value : Double) => {
    let distance = radius * (value - low) / (high - low)
    let alpha = index.to_double() * angle
    (
      center_x + distance * @math.sin(alpha),
      center_y - distance * @math.cos(alpha),
    )
  }
  if !self.grid_pen.0.is_empty() {
    let grid : Array[@layout.PathSegment] = []
    for i in 0..<=ticks {
      let value = high - i.to_double() * step
      for j in 0..<count {
        let (x, y) = point(j, value)
        grid.push(if j == 0 { Move(x, y) } else { Line(x, y) })
      }
      let (x, y) = point(0, value)
      grid.push(Line(x, y))
    }
    out.push(radar_path(grid, self.grid_pen, join=self.grid_join))
  }
  for i, series in data.series {
    let style = styles[i]
    let points = series.values.mapi((index, value) => {
      if self.filled {
        Some(point(index, value.unwrap_or(0)))
      } else {
        value.map(value => point(index, value))
      }
    })
    let path : Array[@layout.PathSegment] = []
    if self.filled {
      for j, position in points {
        let (x, y) = position.unwrap()
        path.push(if j == 0 { Move(x, y) } else { Line(x, y) })
        if j > 0 {
          path.push(Line(x, y))
        }
      }
      let (x, y) = points[0].unwrap()
      path.push(Line(x, y))
      // ONLYOFFICE registers the same completed filled radar path twice.
      for _ in 0..<2 {
        out.push(
          radar_path(
            path,
            (style.line.color, style.line.width),
            fill=style.fill,
            dash=style.dash,
            join=style.join,
          ),
        )
      }
    } else {
      let mut connected = false
      for position in points {
        if position is Some((x, y)) {
          path.push(if connected { Line(x, y) } else { Move(x, y) })
          connected = true
        } else {
          connected = false
        }
      }
      if connected && points[0] is Some((x, y)) {
        path.push(
          if points.all(p => p is Some(_)) {
            Close
          } else {
            Line(x, y)
          },
        )
      }
      out.push(
        radar_path(
          path,
          (style.line.color, style.line.width),
          dash=style.dash,
          join=style.join,
        ),
      )
    }
  }
  if !self.filled {
    for i, series in data.series {
      for index, value in series.values {
        if value is Some(value) {
          let (x, y) = point(index, value)
          styles[i].line.marker_at(out, x, y)
        }
      }
    }
  }
  out
}
