///|
fn Object::line_points(self : Object) -> Array[(Double, Double)] {
  if self.preset == "curvedConnector3" {
    let bend = self.adjustments.0
    [
      (0, 0),
      (bend / 2, 0),
      (bend, 0.25),
      (bend, 0.5),
      (bend, 0.75),
      ((1 + bend) / 2, 1),
      (1, 1),
    ]
  } else if self.polyline.is_empty() {
    [(0, 0), (1, 1)]
  } else {
    self.polyline
  }
}

///|
fn Object::line_path(
  self : Object,
  geometry : Geometry,
) -> Array[@layout.PathSegment] {
  let points = self
    .line_points()
    .map(p => (p.0 * geometry.width, p.1 * geometry.height))
  if self.preset == "curvedConnector3" {
    let (a, b, c, d, e, f, g) = (
      points[0],
      points[1],
      points[2],
      points[3],
      points[4],
      points[5],
      points[6],
    )
    [
      Move(a.0, a.1),
      Cubic(b.0, b.1, c.0, c.1, d.0, d.1),
      Cubic(e.0, e.1, f.0, f.1, g.0, g.1),
    ]
  } else {
    points.mapi((index, p) => {
      if index == 0 {
        Move(p.0, p.1)
      } else {
        Line(p.0, p.1)
      }
    })
  }
}

///|
fn Object::curve_hit(
  self : Object,
  geometry : Geometry,
  x : Double,
  y : Double,
  margin : Double,
) -> Bool {
  if self.stroke.is_empty() {
    return false
  }
  let points = self
    .line_points()
    .map(p => (p.0 * geometry.width, p.1 * geometry.height))
  cubic_hit(points[0], points[1], points[2], points[3], x, y, margin, 0) ||
  cubic_hit(points[3], points[4], points[5], points[6], x, y, margin, 0)
}

///|
fn cubic_hit(
  a : (Double, Double),
  b : (Double, Double),
  c : (Double, Double),
  d : (Double, Double),
  x : Double,
  y : Double,
  margin : Double,
  depth : Int,
) -> Bool {
  if x < a.0.min(b.0).min(c.0).min(d.0) - margin ||
    x > a.0.max(b.0).max(c.0).max(d.0) + margin ||
    y < a.1.min(b.1).min(c.1).min(d.1) - margin ||
    y > a.1.max(b.1).max(c.1).max(d.1) + margin {
    return false
  }
  let dx = d.0 - a.0
  let dy = d.1 - a.1
  let square = dx * dx + dy * dy
  let cross_b = (b.0 - a.0) * dy - (b.1 - a.1) * dx
  let cross_c = (c.0 - a.0) * dy - (c.1 - a.1) * dx
  // Subdivide only for hit testing; rendering retains the native cubic commands.
  if depth == 12 ||
    square == 0 ||
    (
      cross_b * cross_b <= 0.0001 * square &&
      cross_c * cross_c <= 0.0001 * square
    ) {
    let t = if square > 0 {
      (((x - a.0) * dx + (y - a.1) * dy) / square).max(0).min(1)
    } else {
      0.0
    }
    let gx = x - a.0 - t * dx
    let gy = y - a.1 - t * dy
    return gx * gx + gy * gy <= margin * margin
  }
  let ab = ((a.0 + b.0) / 2, (a.1 + b.1) / 2)
  let bc = ((b.0 + c.0) / 2, (b.1 + c.1) / 2)
  let cd = ((c.0 + d.0) / 2, (c.1 + d.1) / 2)
  let abc = ((ab.0 + bc.0) / 2, (ab.1 + bc.1) / 2)
  let bcd = ((bc.0 + cd.0) / 2, (bc.1 + cd.1) / 2)
  let middle = ((abc.0 + bcd.0) / 2, (abc.1 + bcd.1) / 2)
  cubic_hit(a, ab, abc, middle, x, y, margin, depth + 1) ||
  cubic_hit(middle, bcd, cd, d, x, y, margin, depth + 1)
}
