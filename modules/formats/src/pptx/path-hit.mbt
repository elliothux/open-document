///|
fn cubic_coordinate(
  a : Double,
  b : Double,
  c : Double,
  d : Double,
  t : Double,
) -> Double {
  let u = 1.0 - t
  u * u * u * a + 3.0 * u * u * t * b + 3.0 * u * t * t * c + t * t * t * d
}

///|
fn line_winding(
  a : (Double, Double),
  b : (Double, Double),
  x : Double,
  y : Double,
) -> Int32 {
  if (a.1 > y) != (b.1 > y) && x < a.0 + (b.0 - a.0) * (y - a.1) / (b.1 - a.1) {
    if b.1 > a.1 {
      1
    } else {
      -1
    }
  } else {
    0
  }
}

///|
fn cubic_winding(
  a : (Double, Double),
  b : (Double, Double),
  c : (Double, Double),
  d : (Double, Double),
  x : Double,
  y : Double,
) -> Int32 {
  let qa = -a.1 + 3 * b.1 - 3 * c.1 + d.1
  let qb = 2.0 * (a.1 - 2.0 * b.1 + c.1)
  let qc = b.1 - a.1
  let splits = [0.0, 1.0]
  if qa == 0 {
    if qb != 0 {
      let root = -qc / qb
      if root > 0 && root < 1 {
        splits.push(root)
      }
    }
  } else {
    let discriminant = qb * qb - 4.0 * qa * qc
    if discriminant >= 0 {
      for
        root in [
          (-qb - discriminant.sqrt()) / (2.0 * qa),
          (-qb + discriminant.sqrt()) / (2.0 * qa),
        ] {
        if root > 0 && root < 1 {
          splits.push(root)
        }
      }
    }
  }
  splits.sort()
  let mut winding = 0
  for index in 0..<(splits.length() - 1) {
    let mut low = splits[index]
    let mut high = splits[index + 1]
    let from = cubic_coordinate(a.1, b.1, c.1, d.1, low)
    let to = cubic_coordinate(a.1, b.1, c.1, d.1, high)
    if (from > y) == (to > y) {
      continue
    }
    // Derivative roots divide any cubic into monotone intervals.
    for _ in 0..<40 {
      let middle = (low + high) / 2
      if (cubic_coordinate(a.1, b.1, c.1, d.1, middle) < y) == (to > from) {
        low = middle
      } else {
        high = middle
      }
    }
    if x < cubic_coordinate(a.0, b.0, c.0, d.0, (low + high) / 2) {
      winding += if to > from { 1 } else { -1 }
    }
  }
  winding
}

///|
fn path_hit(
  path : Array[@layout.PathSegment],
  fill : Bool,
  stroke : Bool,
  x : Double,
  y : Double,
  margin : Double,
) -> Bool {
  let mut current = (0.0, 0.0)
  let mut first = current
  let mut winding = 0
  for segment in path {
    let next = match segment {
      Move(nx, ny) => {
        if fill {
          winding += line_winding(current, first, x, y)
        }
        current = (nx, ny)
        first = current
        continue
      }
      Line(nx, ny) => (nx, ny)
      Cubic(_, _, _, _, nx, ny) => (nx, ny)
      Close => first
    }
    let (a, b) = match segment {
      Cubic(ax, ay, bx, by, _, _) => ((ax, ay), (bx, by))
      _ => (current, next)
    }
    if stroke && cubic_hit(current, a, b, next, x, y, margin, 0) {
      return true
    }
    if fill {
      winding += match segment {
        Cubic(_, _, _, _, _, _) => cubic_winding(current, a, b, next, x, y)
        _ => line_winding(current, next, x, y)
      }
    }
    current = next
  }
  if fill {
    winding += line_winding(current, first, x, y)
  }
  fill && winding != 0
}
