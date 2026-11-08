///|
fn stroke_cubic(
  points : Array[(Double, Double)],
  a : (Double, Double),
  b : (Double, Double),
  c : (Double, Double),
  d : (Double, Double),
  depth : Int32,
) -> Unit raise @failure.Failure {
  guard [a, b, c, d].all(p => {
    !p.0.is_nan() &&
    !p.1.is_nan() &&
    p.0.abs() <= 1000000000 &&
    p.1.abs() <= 1000000000
  }) else {
    @failure.reject("limit-exceeded", "Stroke curve coordinates exceed budget")
  }
  let dx = d.0 - a.0
  let dy = d.1 - a.1
  let chord = dx * dx + dy * dy
  let error = ((b.0 - d.0) * dy - (b.1 - d.1) * dx).abs() +
    ((c.0 - d.0) * dy - (c.1 - d.1) * dx).abs()
  let within = chord > 0 &&
    [b, c].all(p => {
      let projection = (p.0 - a.0) * dx + (p.1 - a.1) * dy
      if projection < 0 {
        (p.0 - a.0) * (p.0 - a.0) + (p.1 - a.1) * (p.1 - a.1) <= 0.0009765625
      } else if projection > chord {
        (p.0 - d.0) * (p.0 - d.0) + (p.1 - d.1) * (p.1 - d.1) <= 0.0009765625
      } else {
        true
      }
    })
  // Use the existing 1/32 pt shadow tessellation tolerance for stroked curves.
  if (within && error * error <= 0.0009765625 * chord) ||
    (
      chord == 0 &&
      (b.0 - a.0)
      .abs()
      .max((b.1 - a.1).abs())
      .max((c.0 - a.0).abs())
      .max((c.1 - a.1).abs()) <=
      0.03125
    ) {
    if points.last() != Some(d) {
      guard points.length() < 4096 else {
        @failure.reject(
          "limit-exceeded", "Stroke curve subdivision exceeds budget",
        )
      }
      points.push(d)
    }
    return
  }
  guard depth < 12 else {
    @failure.reject("limit-exceeded", "Stroke curve subdivision exceeds budget")
  }
  let ab = ((a.0 + b.0) / 2, (a.1 + b.1) / 2)
  let bc = ((b.0 + c.0) / 2, (b.1 + c.1) / 2)
  let cd = ((c.0 + d.0) / 2, (c.1 + d.1) / 2)
  let abc = ((ab.0 + bc.0) / 2, (ab.1 + bc.1) / 2)
  let bcd = ((bc.0 + cd.0) / 2, (bc.1 + cd.1) / 2)
  let middle = ((abc.0 + bcd.0) / 2, (abc.1 + bcd.1) / 2)
  stroke_cubic(points, a, ab, abc, middle, depth + 1)
  stroke_cubic(points, middle, bcd, cd, d, depth + 1)
}

///|
pub fn stroke_contour(
  path : Array[PathSegment],
  width : Double,
  cap : String,
  join : String,
  miter : Double,
) -> Array[PathSegment] raise @failure.Failure {
  let radius = width / 2
  let result : Array[PathSegment] = []
  guard radius > 0 else { return result }
  let polygon = fn(points : Array[(Double, Double)]) {
    let mut area = 0.0
    for i in 0..<points.length() {
      let a = points[i]
      let b = points[(i + 1) % points.length()]
      area += a.0 * b.1 - a.1 * b.0
    }
    let points = if area < 0 { points.rev() } else { points }
    for i, (x, y) in points {
      result.push(if i == 0 { Move(x, y) } else { Line(x, y) })
    }
    result.push(Close)
  }
  let circle = fn(center : (Double, Double)) {
    for segment in basic_shape_path("ellipse", width, width) {
      result.push(
        match segment {
          Move(x, y) => Move(x + center.0 - radius, y + center.1 - radius)
          Line(x, y) => Line(x + center.0 - radius, y + center.1 - radius)
          Cubic(a, b, c, d, x, y) =>
            Cubic(
              a + center.0 - radius,
              b + center.1 - radius,
              c + center.0 - radius,
              d + center.1 - radius,
              x + center.0 - radius,
              y + center.1 - radius,
            )
          Close => Close
        },
      )
    }
  }
  let direction = fn(a : (Double, Double), b : (Double, Double)) {
    let dx = b.0 - a.0
    let dy = b.1 - a.1
    let length = (dx * dx + dy * dy).sqrt()
    (dx / length, dy / length)
  }
  let ring = fn(points : Array[(Double, Double)]) {
    guard points.length() >= 3 else { return false }
    let left : Array[(Double, Double)] = []
    let right : Array[(Double, Double)] = []
    let mut turn = 0.0
    for i in 0..<points.length() {
      let point = points[i]
      let a = direction(
        points[(i + points.length() - 1) % points.length()],
        point,
      )
      let b = direction(point, points[(i + 1) % points.length()])
      let dot = a.0 * b.0 + a.1 * b.1
      let cross = a.0 * b.1 - a.1 * b.0
      // Subdivision vertices on a smooth convex curve need no separate join pieces.
      guard dot > 0.99 && turn * cross >= 0 else { return false }
      if cross != 0 {
        turn = cross
      }
      let factor = radius / (1 + dot)
      let nx = -(a.1 + b.1) * factor
      let ny = (a.0 + b.0) * factor
      left.push((point.0 + nx, point.1 + ny))
      right.push((point.0 - nx, point.1 - ny))
    }
    guard turn != 0 else { return false }
    let inner = if turn > 0 { left } else { right }
    let outer = if turn > 0 { right } else { left }
    for i in 0..<points.length() {
      let next = (i + 1) % points.length()
      guard (inner[next].0 - inner[i].0) * (points[next].0 - points[i].0) +
        (inner[next].1 - inner[i].1) * (points[next].1 - points[i].1) >
        0 else {
        return false
      }
    }
    polygon(outer)
    let hole = if turn > 0 { inner.rev() } else { inner }
    for i, point in hole {
      result.push(
        if i == 0 {
          Move(point.0, point.1)
        } else {
          Line(point.0, point.1)
        },
      )
    }
    result.push(Close)
    true
  }
  let contour = fn(
    points : Array[(Double, Double)],
    closed : Bool,
    curved : Bool,
  ) {
    guard !points.is_empty() else { return }
    if closed && curved && ring(points) {
      return
    }
    if points.length() == 1 {
      if cap == "rnd" {
        circle(points[0])
      }
      return
    }
    let count = points.length() - (if closed { 0 } else { 1 })
    for index in 0..<count {
      let a = points[index]
      let b = points[(index + 1) % points.length()]
      let t = direction(a, b)
      let n = (-t.1 * radius, t.0 * radius)
      let extend_a = if !closed && cap == "sq" && index == 0 {
        radius
      } else {
        0.0
      }
      let extend_b = if !closed && cap == "sq" && index == count - 1 {
        radius
      } else {
        0.0
      }
      let a = (a.0 - t.0 * extend_a, a.1 - t.1 * extend_a)
      let b = (b.0 + t.0 * extend_b, b.1 + t.1 * extend_b)
      polygon([
        (a.0 + n.0, a.1 + n.1),
        (a.0 - n.0, a.1 - n.1),
        (b.0 - n.0, b.1 - n.1),
        (b.0 + n.0, b.1 + n.1),
      ])
    }
    for
      index in (if closed { 0 } else { 1 })..<(if closed {
        points.length()
      } else {
        points.length() - 1
      }) {
      let center = points[index]
      let a = direction(
        points[(index + points.length() - 1) % points.length()],
        center,
      )
      let b = direction(center, points[(index + 1) % points.length()])
      let cross = a.0 * b.1 - a.1 * b.0
      if cross == 0 {
        continue
      }
      if join == "round" {
        circle(center)
        continue
      }
      let side = if cross > 0 { -radius } else { radius }
      let first = (-a.1 * side, a.0 * side)
      let last = (-b.1 * side, b.0 * side)
      let divisor = 1.0 + a.0 * b.0 + a.1 * b.1
      let corner = ((first.0 + last.0) / divisor, (first.1 + last.1) / divisor)
      let points = [center, (center.0 + first.0, center.1 + first.1)]
      if join == "miter" &&
        divisor > 0 &&
        corner.0 * corner.0 + corner.1 * corner.1 <=
        radius * radius * miter * miter {
        points.push((center.0 + corner.0, center.1 + corner.1))
      }
      points.push((center.0 + last.0, center.1 + last.1))
      polygon(points)
    }
    if !closed && cap == "rnd" {
      circle(points[0])
      circle(points.last().unwrap())
    }
  }
  let points : Array[(Double, Double)] = []
  let mut curved = false
  let mut smooth = true
  let mut initial_tangent : (Double, Double)? = None
  let mut tangent : (Double, Double)? = None
  let aligned = fn(a : (Double, Double), b : (Double, Double)) {
    let a = direction((0, 0), a)
    let b = direction((0, 0), b)
    a.0 * b.0 + a.1 * b.1 > 0.9999999999
  }
  for segment in path {
    match segment {
      Move(x, y) => {
        contour(points, false, curved)
        points.clear()
        points.push((x, y))
        curved = false
        smooth = true
        initial_tangent = None
        tangent = None
      }
      Line(x, y) =>
        if points.last() != Some((x, y)) {
          points.push((x, y))
          smooth = false
        }
      Close => {
        if points.length() > 1 && points.last() == points.get(0) {
          ignore(points.pop())
        }
        if initial_tangent is Some(first) &&
          tangent is Some(last) &&
          !aligned(last, first) {
          smooth = false
        }
        contour(points, true, curved && smooth)
        points.clear()
        curved = false
        smooth = true
        initial_tangent = None
        tangent = None
      }
      Cubic(a, b, c, d, x, y) => {
        guard points.last() is Some(start) else {
          @failure.reject(
            "invalid-drawing", "Stroke curve requires a starting point",
          )
        }
        let first = [
            (a - start.0, b - start.1),
            (c - start.0, d - start.1),
            (x - start.0, y - start.1),
          ]
          .iter()
          .find_first(p => p.0 != 0 || p.1 != 0)
        let last = [(x - c, y - d), (x - a, y - b), (x - start.0, y - start.1)]
          .iter()
          .find_first(p => p.0 != 0 || p.1 != 0)
        if first is Some(first) {
          if tangent is Some(previous) && !aligned(previous, first) {
            smooth = false
          }
          if initial_tangent is None {
            initial_tangent = Some(first)
          }
        }
        if last is Some(last) {
          tangent = Some(last)
        }
        stroke_cubic(points, start, (a, b), (c, d), (x, y), 0)
        curved = true
      }
    }
    guard result.length() <= 4096 else {
      @failure.reject("limit-exceeded", "Stroke contour exceeds budget")
    }
  }
  contour(points, false, curved)
  guard result.length() <= 4096 else {
    @failure.reject("limit-exceeded", "Stroke contour exceeds budget")
  }
  result
}
