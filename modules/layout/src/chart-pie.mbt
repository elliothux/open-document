///|
pub fn ChartData::pie_slices(
  self : ChartData,
  series~ : Int32 = 0,
) -> Array[(Double, Double)] {
  let values = self.series[series].values.map(v => v.unwrap_or(0).abs())
  let maximum = values.fold(init=0.0, (a, b) => a.max(b))
  if maximum == 0 {
    return values.map(_ => (0.0, 0.0))
  }
  // Scale before summing so finite source values cannot overflow the total.
  let weights = values.map(v => v / maximum)
  let total = weights.fold(init=0.0, (a, b) => a + b)
  let slices : Array[(Double, Double)] = []
  let mut used = 0.0
  for weight in weights {
    let start = used / total
    used += weight
    slices.push((start, used / total))
  }
  slices
}

///|
/// Build a closed circular sector, with optional inner radius and native Office arc subdivision.
///
/// ```mbt check
/// test "Circular sectors retain closed inner-radius geometry" {
///   let path = @layout.circular_sector(0, 0.25, 10, 10, 8, inner=4)
///   assert_true(path.length() >= 5)
/// }
/// ```
pub fn circular_sector(
  start : Double,
  end : Double,
  x : Double,
  y : Double,
  radius : Double,
  inner~ : Double = 0,
  office~ : Bool = false,
) -> Array[PathSegment] raise @failure.Failure {
  guard [start, end, x, y, radius, inner].all(value => {
      !value.is_nan() && !value.is_inf() && value.abs() <= 1000000000
    }) &&
    start >= -2 &&
    end <= 3 &&
    end >= start &&
    end - start <= 1.000000000001 &&
    radius >= 0 &&
    radius <= 14400 &&
    inner >= 0 &&
    inner <= radius &&
    x.abs() + radius <= 1000000000 &&
    y.abs() + radius <= 1000000000 else {
    @failure.reject("invalid-chart", "Circular sector geometry exceeds bounds")
  }
  let angle = start * 2 * @math.PI - @math.PI / 2
  let sweep = (end - start) * 2 * @math.PI
  let edges = [angle]
  if office {
    let quarter = @math.PI / 2
    let mut edge = (angle / quarter).floor() * quarter + quarter
    while edge < angle + sweep - 0.000000000001 {
      edges.push(edge)
      edge += quarter
    }
  } else {
    let count = (sweep / (@math.PI / 2)).ceil().to_int().max(1)
    for i in 1..<count {
      edges.push(angle + sweep * i.to_double() / count.to_double())
    }
  }
  edges.push(angle + sweep)
  let native_ring = office && inner > 0
  let edges = if native_ring { edges.rev() } else { edges }
  let count = edges.length() - 1
  let first = edges[0]
  let last = edges[count]
  let path : Array[PathSegment] = if inner == 0 {
    [
      Move(x, y),
      Line(x + radius * @math.cos(first), y + radius * @math.sin(first)),
    ]
  } else if native_ring {
    [
      Move(x + inner * @math.cos(first), y + inner * @math.sin(first)),
      Line(x + radius * @math.cos(first), y + radius * @math.sin(first)),
    ]
  } else {
    [Move(x + radius * @math.cos(first), y + radius * @math.sin(first))]
  }
  for i in 0..<count {
    let a = edges[i]
    let b = edges[i + 1]
    let k = chart_arc_control(b - a, office)
    let x0 = x + radius * @math.cos(a)
    let y0 = y + radius * @math.sin(a)
    let x1 = x + radius * @math.cos(b)
    let y1 = y + radius * @math.sin(b)
    path.push(
      Cubic(
        x0 - k * radius * @math.sin(a),
        y0 + k * radius * @math.cos(a),
        x1 + k * radius * @math.sin(b),
        y1 - k * radius * @math.cos(b),
        x1,
        y1,
      ),
    )
  }
  if inner > 0 {
    path.push(Line(x + inner * @math.cos(last), y + inner * @math.sin(last)))
    for i in 0..<count {
      let a = edges[count - i]
      let b = edges[count - i - 1]
      let k = chart_arc_control(b - a, office)
      let x0 = x + inner * @math.cos(a)
      let y0 = y + inner * @math.sin(a)
      let x1 = x + inner * @math.cos(b)
      let y1 = y + inner * @math.sin(b)
      path.push(
        Cubic(
          x0 - k * inner * @math.sin(a),
          y0 + k * inner * @math.cos(a),
          x1 + k * inner * @math.sin(b),
          y1 - k * inner * @math.cos(b),
          x1,
          y1,
        ),
      )
    }
  }
  // Office rings return to the start geometrically, leaving the stroke seam open.
  path.push(if native_ring { Move(x, y) } else { Close })
  path
}

///|
fn chart_arc_control(sweep : Double, office : Bool) -> Double {
  if office {
    let tangent = @math.tan(sweep / 2)
    @math.sin(sweep) * ((4.0 + 3 * tangent * tangent).sqrt() - 1) / 3
  } else {
    4.0 / 3 * @math.tan(sweep / 4)
  }
}

///|
/// Paints native unlabelled circular charts with explicit per-point fills.
///
/// ```mbt check
/// test "Native circular charts retain explicit per-point fills" {
///   let data : @layout.ChartData = {
///     kind: "doughnut",
///     hole_size: Some(50),
///     legend: "none",
///     title: "",
///     label: "",
///     categories: ["A", "B"],
///     series: [{ name: "Values", values: [Some(25), Some(75)], }],
///   }
///   let paths = data.paint_native_pie(
///     200,
///     100,
///     [[("ff0000", 0.5), ("0000ff", 1)]],
///     [(0, [0, 0])],
///     90,
///   )
///   assert_eq(paths.length(), 2)
/// }
/// ```
pub fn ChartData::paint_native_pie(
  self : ChartData,
  width : Double,
  height : Double,
  colors : Array[Array[(String, Double)]],
  explosions : Array[(Double, Array[Double])],
  first_angle : Double,
) -> Array[PositionedPrimitive] raise @failure.Failure {
  self.validate()
  guard ["pie", "doughnut"].contains(self.kind) &&
    (self.kind == "doughnut" || self.series.length() == 1) &&
    width >= 24 &&
    width <= 14400 &&
    height >= 24 &&
    height <= 14400 &&
    colors.length() == self.series.length() &&
    explosions.length() == self.series.length() &&
    explosions.all(e => {
      e.0 >= 0 &&
      e.0 <= 400 &&
      e.1.length() == self.categories.length() &&
      e.1.all(value => value >= 0 && value <= e.0)
    }) &&
    first_angle >= 0 &&
    first_angle <= 360 else {
    @failure.reject("invalid-chart", "Invalid native circular chart geometry")
  }
  let count = self.series.length()
  let parent_explosion = explosions[count - 1].0
  // ONLYOFFICE 10.0.0.170 uses fourteen CSS pixels around an unlabelled plot.
  let radius = (width.min(height) - 21) / 2 / (1 + parent_explosion / 100)
  let hole = radius * self.hole_size.unwrap_or(0).to_double() / 100
  let step = (radius - hole) / count.to_double()
  let out : Array[PositionedPrimitive] = []
  for series in 0..<count {
    guard colors[series].length() == self.categories.length() &&
      explosions[series].1.length() == self.categories.length() else {
      @failure.reject("invalid-chart", "Native circular chart points disagree")
    }
    for index, (start, end) in self.pie_slices(series~) {
      let (color, alpha) = colors[series][index]
      let explosion = if series == count - 1 {
        explosions[series].1[index]
      } else {
        0.0
      }
      guard alpha >= 0 &&
        alpha <= 1 &&
        explosion >= 0 &&
        explosion <= parent_explosion &&
        color.length() == 6 &&
        color.iter().all(c => (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) else {
        @failure.reject("invalid-chart", "Invalid native circular chart style")
      }
      if end <= start {
        continue
      }
      let middle = (start + end) * @math.PI +
        first_angle * @math.PI / 180 -
        @math.PI / 2
      let x = width / 2 + radius * explosion / 100 * @math.cos(middle)
      let y = height / 2 + radius * explosion / 100 * @math.sin(middle)
      out.push(
        Path(
          circular_sector(
            start + first_angle / 360,
            end + first_angle / 360,
            x,
            y,
            hole + step * (series + 1).to_double(),
            inner=hole + step * series.to_double(),
            office=true,
          ),
          color,
          "",
          0,
          {
            evenOdd: false,
            fillAlpha: alpha,
            strokeAlpha: 1,
            dash: [],
            cap: 0,
            join: 0,
            miter: 10,
          },
        ),
      )
    }
  }
  out
}

///|
fn ChartData::paint_pie(
  self : ChartData,
  width : Double,
  height : Double,
  colors : Array[String],
) -> Array[PositionedPrimitive] raise @failure.Failure {
  let data = self
  let out : Array[PositionedPrimitive] = []
  let area = width
  let radius = (area - 20).min(height - 62) / 2
  let x = area / 2
  let y = 48.0 + (height - 62) / 2
  let rings = if data.kind == "doughnut" { data.series.length() } else { 1 }
  let hole = radius * data.hole_size.unwrap_or(0).to_double() / 100
  let thickness = (radius - hole) / rings.to_double()
  let mut ring = 0
  for series in 0..<rings {
    for index, (start, end) in data.pie_slices(series~) {
      if end > start {
        out.push(
          Path(
            circular_sector(
              start,
              end,
              x,
              y,
              hole + thickness * (ring + 1).to_double(),
              inner=hole + thickness * ring.to_double(),
            ),
            chart_paint_color(colors, index),
            "",
            0,
            {
              evenOdd: false,
              fillAlpha: 1,
              strokeAlpha: 1,
              dash: [],
              cap: 0,
              join: 0,
              miter: 8,
            },
          ),
        )
      }
    }
    if data.series[series].values.any(value => value is Some(_)) {
      ring += 1
    }
  }
  out
}
