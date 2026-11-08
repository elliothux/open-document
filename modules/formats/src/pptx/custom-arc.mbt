///|
fn custom_arc(
  current : (Double, Double),
  rx : Double,
  ry : Double,
  start : Double,
  sweep : Double,
  sx : Double,
  sy : Double,
) -> Array[@layout.PathSegment] {
  guard rx > 0 && ry > 0 && sweep != 0 else { return [] }
  let angle = fn(value : Double) {
    let radians = value * @math.PI / 10800000
    let ray = @math.atan2(sy * @math.sin(radians), sx * @math.cos(radians))
    @math.atan2(rx * @math.sin(ray), ry * @math.cos(ray))
  }
  let a = angle(start)
  let b = angle(start + sweep)
  let b = if sweep > 0 && b <= a {
    b + 2 * @math.PI
  } else if sweep < 0 && b >= a {
    b - 2 * @math.PI
  } else {
    b
  }
  let cx = current.0 - rx * @math.cos(a)
  let cy = current.1 - ry * @math.sin(a)
  if sweep.abs() == 21600000 {
    let k = 0.552
    return [
      Move(cx - rx, cy),
      Cubic(cx - rx, cy + k * ry, cx - k * rx, cy + ry, cx, cy + ry),
      Cubic(cx + k * rx, cy + ry, cx + rx, cy + k * ry, cx + rx, cy),
      Cubic(cx + rx, cy - k * ry, cx + k * rx, cy - ry, cx, cy - ry),
      Cubic(cx - k * rx, cy - ry, cx - rx, cy - k * ry, cx - rx, cy),
    ]
  }
  let points = [a]
  let quarter = @math.PI / 2
  let step = if sweep > 0 { quarter } else { -quarter }
  let mut next = if sweep > 0 {
    (a / quarter).floor() * quarter + quarter
  } else {
    (a / quarter).ceil() * quarter - quarter
  }
  while (if sweep > 0 { next < b - 1.0e-12 } else { next > b + 1.0e-12 }) {
    points.push(next)
    next += step
  }
  points.push(b)
  let path : Array[@layout.PathSegment] = []
  for index in 0..<(points.length() - 1) {
    let a = points[index]
    let b = points[index + 1]
    let delta = b - a
    let tangent = @math.tan(delta / 2)
    let k = @math.sin(delta) * ((4.0 + 3 * tangent * tangent).sqrt() - 1) / 3
    let ax = @math.cos(a)
    let ay = @math.sin(a)
    let bx = @math.cos(b)
    let by = @math.sin(b)
    path.push(
      Cubic(
        cx + rx * (ax - k * ay),
        cy + ry * (ay + k * ax),
        cx + rx * (bx + k * by),
        cy + ry * (by - k * bx),
        cx + rx * bx,
        cy + ry * by,
      ),
    )
  }
  path
}
