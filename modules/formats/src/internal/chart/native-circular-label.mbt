///|
fn circular_ray_box(
  x : Double,
  y : Double,
  width : Double,
  height : Double,
  cx : Double,
  cy : Double,
  ex : Double,
  ey : Double,
) -> Bool {
  let mut low = 0.0
  let mut high = 1.0
  for
    (start, end, first, last) in [
      (cx, ex, x, x + width),
      (cy, ey, y, y + height),
    ] {
    let delta = end - start
    if delta.abs() < 0.000000000001 {
      if start < first || start > last {
        return false
      }
    } else {
      let a = (first - start) / delta
      let b = (last - start) / delta
      low = low.max(a.min(b))
      high = high.min(a.max(b))
      if high < low {
        return false
      }
    }
  }
  true
}

///|
fn circular_fit_label(
  start : Double,
  end : Double,
  radius : Double,
  width : Double,
  height : Double,
  outer : Bool,
) -> (Double, Double)? {
  let tau = 2.0 * @math.PI
  let middle = (start + end) / 2
  let angle = middle - (middle / tau).floor() * tau
  let shifted = angle + @math.PI / 4
  let shifted = shifted - (shifted / tau).floor() * tau - @math.PI / 4
  let area = ((shifted + @math.PI / 4) / (@math.PI / 2)).floor().to_int()
  let f = (shifted + @math.PI / 4) / (@math.PI / 2) - area.to_double()
  let (dx, dy, ox, oy) : (Double, Double, Double, Double) = if outer {
    match area {
      0 =>
        (
          0.0,
          if shifted.abs() < 0.0001 {
            0.0
          } else if shifted < 0 {
            f * height
          } else {
            -(1.0 - f) * height
          },
          0.0,
          -(1.0 - f) * height,
        )
      1 =>
        (
          if (angle - @math.PI / 2).abs() < 0.0001 {
            0.0
          } else if angle < @math.PI / 2 {
            -f * width
          } else {
            (1 - f) * width
          },
          0.0,
          -f * width,
          0.0,
        )
      2 =>
        (
          0.0,
          if (angle - @math.PI).abs() < 0.0001 {
            0.0
          } else if angle < @math.PI {
            -f * height
          } else {
            (1.0 - f) * height
          },
          -width,
          -f * height,
        )
      _ =>
        (
          if angle < 3.0 * @math.PI / 2 {
            f * width
          } else {
            -(1.0 - f) * width
          },
          0.0,
          -(1.0 - f) * width,
          -height,
        )
    }
  } else if [0.0, @math.PI / 2, @math.PI, 3.0 * @math.PI / 2].any(axis => {
      (angle - axis).abs() < 0.000000001
    }) {
    (
      if @math.cos(angle) >= 0 {
        width / 2
      } else {
        -width / 2
      },
      if @math.sin(angle) >= 0 {
        height / 2
      } else {
        -height / 2
      },
      -width / 2,
      -height / 2,
    )
  } else {
    match area {
      0 =>
        (
          width,
          if shifted < 0 {
            -(1.0 - f) * height
          } else {
            f * height
          },
          0.0,
          -(1.0 - f) * height,
        )
      1 =>
        (
          if angle < @math.PI / 2 {
            (1.0 - f) * width
          } else {
            -f * width
          },
          height,
          -f * width,
          0.0,
        )
      2 =>
        (
          -width,
          if angle < @math.PI {
            (1.0 - f) * height
          } else {
            -f * height
          },
          -width,
          -f * height,
        )
      _ =>
        (
          if angle < 3.0 * @math.PI / 2 {
            -(1.0 - f) * width
          } else {
            f * width
          },
          -height,
          -(1.0 - f) * width,
          -height,
        )
    }
  }
  let x = radius * @math.cos(angle)
  let y = radius * @math.sin(angle)
  let a = radius * radius
  let b = 2.0 * (dx * x + dy * y)
  let c = dx * dx + dy * dy - a
  let discriminant = b * b - 4 * a * c
  guard a > 0 && discriminant >= 0 else { return None }
  let root = (-b + discriminant.sqrt()) / (2 * a)
  guard root >= 0 && (outer || root < 1) else { return None }
  Some((root * x + ox, root * y + oy))
}

///|
fn circular_label_position(
  start : Double,
  end : Double,
  radius : Double,
  inner : Double,
  width : Double,
  height : Double,
  position : String,
  doughnut : Bool,
) -> (Double, Double) {
  let angle = (start + end) / 2
  let x = @math.cos(angle)
  let y = @math.sin(angle)
  if doughnut || ["ctr", "inBase"].contains(position) {
    let r = if doughnut { (radius + inner) / 2 } else { radius / 2 }
    return (r * x - width / 2, r * y - height / 2)
  }
  if position == "outEnd" {
    return (
      radius * x - (if x < 0 { width } else { 0 }),
      radius * y - (if y < 0 { height } else { 0 }),
    )
  }
  let fit : (Double, Double)? = if position == "inEnd" {
    let dx = if x >= 0 { width / 2 } else { -width / 2 }
    let dy = if y >= 0 { height / 2 } else { -height / 2 }
    let b = 2.0 * radius * (dx * x + dy * y)
    let c = dx * dx + dy * dy - radius * radius
    let d = b * b - 4.0 * radius * radius * c
    if radius > 0 && d >= 0 {
      let r = (-b + d.sqrt()) / (2 * radius)
      Some((r * x - width / 2, r * y - height / 2))
    } else {
      None
    }
  } else {
    circular_fit_label(start, end, radius, width, height, false)
  }
  if fit is Some((left, top)) &&
    (
      position != "bestFit" ||
      ![start, end].any(angle => {
        circular_ray_box(
          left,
          top,
          width,
          height,
          0,
          0,
          radius * @math.cos(angle),
          radius * @math.sin(angle),
        )
      })
    ) {
    return (left, top)
  }
  if position == "bestFit" &&
    circular_fit_label(start, end, radius, width, height, true) is Some(point) {
    return point
  }
  (radius / 2 * x - width / 2, radius / 2 * y - height / 2)
}
