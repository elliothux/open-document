///|
fn line_curve_paths(
  points : Array[(Double, Double)],
  smooth : Bool,
  units : (Double, Double),
  plot : @layout.Border,
) -> Array[Array[@layout.PathSegment]] {
  guard points.get(0) is Some((x, y)) else { return [] }
  let point = fn(x : Double, y : Double) {
    (x, y.max(plot.y).min(plot.y + plot.height))
  }
  if !smooth {
    if points.all(p => p == (x, y)) {
      return [[]]
    }
    let (x, y) = point(x, y)
    return [
      [
        Move(x, y),
        ..points[1:].map(p => {
          let (x, y) = point(p.0, p.1)
          @layout.Line(x, y)
        }),
      ],
    ]
  }
  let paths : Array[Array[@layout.PathSegment]] = []
  let distance = fn(a : (Double, Double), b : (Double, Double)) {
    let x = (a.0 - b.0) / units.0
    let y = (a.1 - b.1) / units.1
    (x * x + y * y).sqrt()
  }
  for i in 1..<points.length() {
    let (x1, y1) = points[i - 1]
    let (x2, y2) = points[i]
    let (x0, y0) = points[(i - 2).max(0)]
    let (x3, y3) = points[(i + 1).min(points.length() - 1)]
    let d12 = distance((x1, y1), (x2, y2))
    if d12 == 0 {
      // Keep the source segment index without painting a degenerate stroke.
      paths.push([])
      continue
    }
    let d02 = distance((x0, y0), (x2, y2))
    let d13 = distance((x1, y1), (x3, y3))
    // ONLYOFFICE ChartsDrawer.calculate_Bezier: bound the chord tangents at half the segment.
    let (a, b) = if d02 / 6 < d12 / 2 && d13 / 6 < d12 / 2 {
      (
        if x0 == x1 {
          1.0 / 3
        } else {
          1.0 / 6
        },
        if x2 == x3 {
          1.0 / 3
        } else {
          1.0 / 6
        },
      )
    } else if d02 / 6 >= d12 / 2 && d13 / 6 >= d12 / 2 {
      (
        if d02 == 0 {
          0.0
        } else {
          d12 / 2 / d02
        },
        if d13 == 0 {
          0.0
        } else {
          d12 / 2 / d13
        },
      )
    } else {
      let length = d02.max(d13)
      let factor = if length == 0 { 0.0 } else { d12 / 2 / length }
      (factor, factor)
    }
    let (cx1, cy1) = (x1 + (x2 - x0) * a, y1 + (y2 - y0) * a)
    let (cx2, cy2) = (x2 + (x1 - x3) * b, y2 + (y1 - y3) * b)
    let (x, y) = point(x1, y1)
    let path : Array[@layout.PathSegment] = [Move(x, y)]
    // Native calculateSplineLine samples each data-coordinate cubic at t = 0, 0.1, ..., 1.
    for j in 0..<=10 {
      let t = j.to_double() / 10
      let u = 1.0 - t
      let (x, y) = point(
        u * u * u * x1 +
        3.0 * t * u * u * cx1 +
        3.0 * t * t * u * cx2 +
        t * t * t * x2,
        u * u * u * y1 +
        3.0 * t * u * u * cy1 +
        3.0 * t * t * u * cy2 +
        t * t * t * y2,
      )
      path.push(Line(x, y))
    }
    paths.push(path)
  }
  paths
}

///|
priv struct LinePolynomial {
  coefficients : Array[Double]
  center : Double
  scale : Double
  equation : Array[Double]
  r_squared : Double
}

///|
fn LinePolynomial::value(self : LinePolynomial, x : Double) -> Double {
  let t = (x - self.center) / self.scale
  self.coefficients
  .rev_iter()
  .fold(init=0.0, (value, coefficient) => value * t + coefficient)
}

///|
fn line_polynomial(
  values : Array[Double?],
  degree : Int32,
) -> LinePolynomial raise @failure.Failure {
  let points = values
    .mapi((index, value) => value.map(value => ((index + 1).to_double(), value)))
    .filter_map(value => value)
  guard degree >= 2 && degree <= 6 && points.length() >= 2 else {
    @failure.reject(
      "unsupported-chart", "Insufficient polynomial trendline points",
    )
  }
  let degree = degree.min(points.length() - 1)
  let center = (points[0].0 + points[points.length() - 1].0) / 2
  let scale = (points[points.length() - 1].0 - points[0].0) / 2
  let magnitude = points.fold(init=1.0, (maximum, point) => {
    maximum.max(point.1.abs())
  })
  let n = degree + 1
  let matrix = Array::makei(n, _ => Array::make(n + 1, 0.0))
  for (x, y) in points {
    let powers = Array::make(n * 2 - 1, 1.0)
    for i in 1..<powers.length() {
      powers[i] = powers[i - 1] * (x - center) / scale
    }
    for i in 0..<n {
      for j in 0..<n {
        matrix[i][j] += powers[i + j]
      }
      matrix[i][n] += powers[i] * y / magnitude
    }
  }
  for i in 0..<n {
    let mut pivot = i
    for j in (i + 1)..<n {
      if matrix[j][i].abs() > matrix[pivot][i].abs() {
        pivot = j
      }
    }
    guard matrix[pivot][i].abs() > 1.0e-12 else {
      @failure.reject("unsupported-chart", "Singular polynomial trendline")
    }
    let row = matrix[i]
    matrix[i] = matrix[pivot]
    matrix[pivot] = row
    let divisor = matrix[i][i]
    for j in i..<=n {
      matrix[i][j] /= divisor
    }
    for j in 0..<n {
      if j != i {
        let factor = matrix[j][i]
        for k in i..<=n {
          matrix[j][k] -= factor * matrix[i][k]
        }
      }
    }
  }
  let coefficients = matrix.map(row => row[n] * magnitude)
  let raw = Array::make(n, 0.0)
  let mut basis : Array[Double] = [1.0]
  for coefficient in coefficients {
    for i, value in basis {
      raw[i] += coefficient * value
    }
    let next = Array::make(basis.length() + 1, 0.0)
    for i, value in basis {
      next[i] -= center / scale * value
      next[i + 1] += value / scale
    }
    basis = next
  }
  guard coefficients.all(v => !v.is_nan() && !v.is_inf()) &&
    raw.all(v => !v.is_nan() && !v.is_inf()) else {
    @failure.reject(
      "limit-exceeded", "Polynomial trendline exceeds numeric limits",
    )
  }
  let fitted : LinePolynomial = {
    coefficients,
    center,
    scale,
    equation: raw,
    r_squared: 0,
  }
  let mean = points.fold(init=0.0, (sum, point) => sum + point.1 / magnitude) /
    points.length().to_double()
  let total = points.fold(init=0.0, (sum, point) => {
    let delta = point.1 / magnitude - mean
    sum + delta * delta
  })
  let residual = points.fold(init=0.0, (sum, point) => {
    let delta = (point.1 - fitted.value(point.0)) / magnitude
    sum + delta * delta
  })
  {
    ..fitted,
    r_squared: if total == 0 {
      1
    } else {
      (1.0 - residual / total).max(0).min(1)
    },
  }
}

///|
fn line_general(value : Double, digits~ : Int32 = 10) -> String {
  if value == 0 {
    return "0"
  }
  let exponent = @math.log10(value.abs()).floor()
  let factor = @math.pow(10, (digits - 1).to_double() - exponent)
  if factor.is_inf() || factor == 0 || (value * factor).is_inf() {
    return value.to_string()
  }
  ((value * factor).round() / factor).to_string()
}

///|
fn line_coefficient(value : Double) -> String {
  let rounded = (value * 10000).round() / 10000
  if rounded != 0 || value == 0 {
    return rounded.to_string()
  }
  let exponent = @math.log10(value).floor()
  let digit = (value / @math.pow(10, exponent)).round()
  let exponent = if digit == 10 {
    exponent.to_int() + 1
  } else {
    exponent.to_int()
  }
  (if digit == 10 { 1.0 } else { digit }).to_string() +
  "E" +
  (if exponent < 0 { "-" } else { "+" }) +
  exponent.abs().to_string().pad_start(2, '0')
}

///|
fn line_trend_text(
  trend : NativeLineTrend,
  fit : LinePolynomial,
  chart_width : Double,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> @layout.TextBlock raise @failure.Failure {
  let spans : Array[@layout.Span] = []
  let add = fn(text : String, superscript : Bool) {
    spans.push({
      node: 0,
      text,
      style: {
        ..trend.text,
        script: if superscript {
          "superscript"
        } else {
          "baseline"
        },
      },
      drawing: None,
      field: "",
    })
  }
  if trend.equation {
    add("y = ", false)
    for i in 0..<fit.equation.length() {
      let degree = fit.equation.length() - 1 - i
      let coefficient = fit.equation[degree]
      let rounded = line_coefficient(coefficient.abs())
      if rounded == "0" {
        continue
      }
      add(
        (if i > 0 {
          if coefficient < 0 {
            " - "
          } else {
            " + "
          }
        } else if coefficient < 0 {
          "-"
        } else {
          ""
        }) +
        // Native ChartFormat.fillEquationContent appends x even to the constant term.
        rounded +
        "x",
        false,
      )
      if degree > 1 {
        add(degree.to_string(), true)
      }
    }
  }
  if trend.r_squared {
    add((if trend.equation { "\n" } else { "" }) + "R", false)
    add("2", true)
    add(" = " + ((fit.r_squared * 10000).round() / 10000).to_string(), false)
  }
  // Native trend labels use four fifths of the chart width minus both text insets.
  let width = (chart_width * 0.8 - 2 * 2.88).clamp(min=1, max=14400)
  let block = probe.span_block(spans, trend.text.size, profile, width, true)
  line_centered_block(block)
}

///|
fn line_centered_block(block : @layout.TextBlock) -> @layout.TextBlock {
  let unit = 16384.0 * 25.4 / 72
  let widths : Array[Double] = []
  // Chart labels use native character advances rather than Writer's integer-twip run widths.
  let lines = block.lines.mapi((index, line) => {
    let edges : Array[(Double, Double)] = []
    let mut x = 0.0
    let mut visible_width = 0.0
    let line = line.map(primitive => {
      guard primitive is @layout.Text(text) else { return primitive }
      @layout.Text({
        ..text,
        runs: text.runs.mapi((i, run) => {
          let old_end = text.runs
            .get(i + 1)
            .map(next => next.x)
            .unwrap_or(block.widths[index])
          let left = x
          let glyphs = run.glyphs.map(glyph => {
            let at = x - left
            x += (glyph.advance.to_double() * glyph.scale * unit).floor() / unit
            if run.text[glyph.cluster] != ' ' {
              visible_width = x
            }
            { ..glyph, x: at, }
          })
          edges.append([(run.x, left), (old_end, x)])
          { ..run, x: left, glyphs, }
        }),
      })
    })
    widths.push(visible_width)
    let edge = fn(value : Double) {
      edges
      .iter()
      .find_first(pair => (pair.0 - value).abs() < 0.000001)
      .map(pair => pair.1)
      .unwrap_or(value)
    }
    let painted : Array[@layout.PositionedPrimitive] = line.map(primitive => {
      match primitive {
        @layout.Path([Move(left, y), Line(right, at)], fill, stroke, pen, style) if y ==
          at =>
          @layout.Path(
            [
              Move(edge(left).min(visible_width), y),
              Line(edge(right).min(visible_width), at),
            ],
            fill,
            stroke,
            pen,
            style,
          )
        _ => primitive
      }
    })
    painted
  })
  let width = widths.fold(init=0.0, (maximum, value) => maximum.max(value))
  {
    ..block,
    widths,
    lines: lines.mapi((i, line) => {
      let shift = (width - widths[i]) / 2
      [
        @layout.Transform({ a: 1, b: 0, c: 0, d: 1, e: shift, f: 0, }),
        ..line,
        @layout.Restore,
      ]
    }),
  }
}
