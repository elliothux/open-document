///|
priv struct SurfacePoint {
  x : Double
  y : Double
  z : Double
  value : Double
}

///|
fn surface_clip(
  points : Array[SurfacePoint],
  level : Double,
  above : Bool,
) -> Array[SurfacePoint] {
  let out : Array[SurfacePoint] = []
  for index, point in points {
    let previous = points[(index + points.length() - 1) % points.length()]
    let inside = if above { point.value >= level } else { point.value <= level }
    let was_inside = if above {
      previous.value >= level
    } else {
      previous.value <= level
    }
    if inside != was_inside && previous.value != level && point.value != level {
      let t = (level - previous.value) / (point.value - previous.value)
      out.push({
        x: previous.x + t * (point.x - previous.x),
        y: previous.y + t * (point.y - previous.y),
        z: previous.z + t * (point.z - previous.z),
        value: level,
      })
    }
    if inside {
      out.push(point)
    }
  }
  out
}

///|
fn surface_bands(
  data : @layout.ChartData,
  projection : BarProjection,
  low : Double,
  high : Double,
  step : Double,
  between : Bool,
) -> Array[Array[Array[(Double, Double, Double)]]] raise @failure.Failure {
  let count = ((high - low) / step).round().to_int()
  guard count > 0 &&
    count <= 600 &&
    data.series.length() >= 2 &&
    data.categories.length() >= 2 &&
    data.series.all(series => series.values.length() == data.categories.length()) else {
    @failure.reject(
      "invalid-chart", "Surface bands require a bounded grid and axis",
    )
  }
  let bands : Array[Array[Array[(Double, Double, Double)]]] = Array::makei(
    count,
    _ => [],
  )
  let plot = projection.plot
  let grid = data.series.mapi((series, source) => {
    source.values.mapi((category, value) => {
      let value = value.unwrap_or(0)
      SurfacePoint::{
        x: plot.x +
        plot.width *
        (category.to_double() + (if between { 0.5 } else { 0.0 })) /
        (data.categories.length() - (if between { 0 } else { 1 })).to_double(),
        y: plot.y + plot.height * (1 - (value - low) / (high - low)),
        z: projection.depth *
        series.to_double() /
        (data.series.length() - 1).to_double(),
        value,
      }
    })
  })
  let mut work = 0
  for row in 0..<(grid.length() - 1) {
    for column in 0..<(data.categories.length() - 1) {
      let a = grid[row][column]
      let b = grid[row + 1][column]
      let c = grid[row][column + 1]
      let d = grid[row + 1][column + 1]
      // Native surfaces retain planar quads; other cells choose the diagonal by opposite sums.
      let faces = if (a.value + d.value - b.value - c.value).abs() < 1.0e-10 {
        [[a, b, d, c]]
      } else if b.value + c.value < d.value + a.value {
        [[a, d, c], [a, b, d]]
      } else {
        [[a, b, c], [c, b, d]]
      }
      for face in faces {
        let minimum = face.fold(init=face[0].value, (v, p) => v.min(p.value))
        let maximum = face.fold(init=face[0].value, (v, p) => v.max(p.value))
        let first = ((minimum - low) / step)
          .floor()
          .to_int()
          .max(0)
          .min(count - 1)
        let last = ((maximum - low) / step)
          .floor()
          .to_int()
          .max(0)
          .min(count - 1)
        for band in first..<=last {
          work += 1
          guard work <= 131072 else {
            @failure.reject(
              "limit-exceeded", "Surface band intersections exceed budget",
            )
          }
          let clipped = surface_clip(
            surface_clip(face, low + band.to_double() * step, true),
            low + (band + 1).to_double() * step,
            false,
          )
          if clipped.length() < 3 {
            continue
          }
          let projected = clipped.map(p => projection.point(p.x, p.y, p.z))
          let center = projected.fold(init=(0.0, 0.0), (sum, p) => {
            (sum.0 + p.0, sum.1 + p.1)
          })
          let center = (
            center.0 / projected.length().to_double(),
            center.1 / projected.length().to_double(),
          )
          let ordered = projected.map(p => {
            (@math.atan2(p.0 - center.0, p.1 - center.1), p)
          })
          ordered.sort_by((a, b) => b.0.compare(a.0))
          let points : Array[(Double, Double, Double)] = []
          for (angle, point) in ordered {
            if !points.any(p => p.0 == point.0 && p.1 == point.1) {
              ignore(angle)
              points.push(point)
            }
          }
          if points.length() >= 3 {
            bands[band].push(points)
          }
        }
      }
    }
  }
  bands
}
