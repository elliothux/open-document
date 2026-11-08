///|
fn pie_angles(adjustments : (Double, Double, Double)) -> (Double, Double) {
  let start = adjustments.0.clamp(min=0, max=21599999) * @math.PI / 10800000
  let end = adjustments.1.clamp(min=0, max=21599999) * @math.PI / 10800000
  (start, if end > start { end } else { end + 2 * @math.PI })
}

///|
fn pie_path(
  width : Double,
  height : Double,
  adjustments : (Double, Double, Double),
) -> Array[@layout.PathSegment] {
  guard width > 0 && height > 0 else { return [] }
  let (start, end) = pie_angles(adjustments)
  let rx = width / 2
  let ry = height / 2
  if end - start >= 2 * @math.PI - 1.0e-12 {
    // ONLYOFFICE's complete-arc path starts at the left edge with its fixed ellipse controls.
    let k = 0.552
    return [
      Move(0, ry),
      Cubic(0, ry + k * ry, rx - k * rx, height, rx, height),
      Cubic(rx + k * rx, height, width, ry + k * ry, width, ry),
      Cubic(width, ry - k * ry, rx + k * rx, 0, rx, 0),
      Cubic(rx - k * rx, 0, 0, ry - k * ry, 0, ry),
      Line(rx, ry),
      Close,
    ]
  }
  // DrawingML angles name rays from the center, rather than ellipse parameters.
  let parameter = fn(angle : Double) {
    @math.atan2(rx * @math.sin(angle), ry * @math.cos(angle))
  }
  let a = parameter(start)
  let b = parameter(end)
  let b = if b <= a { b + 2 * @math.PI } else { b }
  let points = [a]
  let quarter = @math.PI / 2
  let mut next = (a / quarter).floor() * quarter + quarter
  while next < b - 1.0e-12 {
    points.push(next)
    next += quarter
  }
  points.push(b)
  let first = (rx + rx * @math.cos(a), ry + ry * @math.sin(a))
  let path : Array[@layout.PathSegment] = [Move(first.0, first.1)]
  for i in 0..<(points.length() - 1) {
    let (a, b) = (points[i], points[i + 1])
    let sweep = b - a
    let tangent = @math.tan(sweep / 2)
    let k = @math.sin(sweep) * ((4.0 + 3 * tangent * tangent).sqrt() - 1) / 3
    let (ax, ay) = (@math.cos(a), @math.sin(a))
    let (bx, by) = (@math.cos(b), @math.sin(b))
    path.push(
      Cubic(
        rx + rx * (ax - k * ay),
        ry + ry * (ay + k * ax),
        rx + rx * (bx + k * by),
        ry + ry * (by - k * bx),
        rx + rx * bx,
        ry + ry * by,
      ),
    )
  }
  path.append([Line(rx, ry), Close])
  path
}

///|
fn Object::pie_hit(
  self : Object,
  geometry : Geometry,
  x : Double,
  y : Double,
  margin : Double,
) -> Bool raise @failure.Failure {
  let (w, h) = (geometry.width, geometry.height)
  guard w > 0 && h > 0 else { return false }
  if !self.text().is_empty() {
    let body = self.shape_body(geometry)
    if x >= body.left &&
      x <= w - body.right &&
      y >= body.top &&
      y <= h - body.bottom {
      return true
    }
  }
  let (dx, dy) = (x - w / 2, y - h / 2)
  if self.has_fill() &&
    2.0 * dx / w * (2.0 * dx / w) + 2.0 * dy / h * (2.0 * dy / h) <= 1 {
    if dx == 0 && dy == 0 {
      return true
    }
    let (start, end) = pie_angles(self.adjustments)
    let angle = @math.atan2(dy, dx)
    let angle = if angle < start { angle + 2 * @math.PI } else { angle }
    if angle >= start && angle <= end {
      return true
    }
  }
  guard !self.stroke.is_empty() else { return false }
  let mut previous = (0.0, 0.0)
  let mut first = previous
  for segment in pie_path(w, h, self.adjustments) {
    match segment {
      Move(x, y) => {
        previous = (x, y)
        first = previous
      }
      Cubic(ax, ay, bx, by, cx, cy) => {
        if cubic_hit(previous, (ax, ay), (bx, by), (cx, cy), x, y, margin, 0) {
          return true
        }
        previous = (cx, cy)
      }
      Line(nx, ny) => {
        let next = (nx, ny)
        if cubic_hit(previous, previous, next, next, x, y, margin, 0) {
          return true
        }
        previous = next
      }
      Close =>
        if cubic_hit(previous, previous, first, first, x, y, margin, 0) {
          return true
        }
    }
  }
  false
}
