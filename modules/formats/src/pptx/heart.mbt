///|
fn heart_path(width : Double, height : Double) -> Array[@layout.PathSegment] {
  [
    Move(width / 2, height / 4),
    Cubic(
      width * 17 / 24,
      -height / 3,
      width * 73 / 48,
      height / 4,
      width / 2,
      height,
    ),
    Cubic(
      -width * 25 / 48,
      height / 4,
      width * 7 / 24,
      -height / 3,
      width / 2,
      height / 4,
    ),
    Close,
  ]
}

///|
fn Object::heart_hit(
  self : Object,
  width : Double,
  height : Double,
  x : Double,
  y : Double,
  margin : Double,
) -> Bool {
  guard width > 0 && height > 0 else { return false }
  if self.has_fill() && y >= 0 && y <= height {
    let level = y / height
    let horizontal = 0.5 + (x / width - 0.5).abs()
    let turn = (7.0 - 28.0.sqrt()) / 6
    let ordinate = fn(t) { 0.25 - 1.75 * t + 3.5 * t * t - t * t * t }
    let abscissa = fn(t) {
      0.5 + 0.625 * t + 1.8125 * t * t - 2.4375 * t * t * t
    }
    if level >= ordinate(turn) {
      // Split at the cubic's vertical extremum to retain the notch between the lobes.
      let mut low = turn
      let mut high = 1.0
      for _ in 0..<32 {
        let middle = (low + high) / 2
        if ordinate(middle) < level {
          low = middle
        } else {
          high = middle
        }
      }
      let outer = abscissa((low + high) / 2)
      let inner = if level < 0.25 {
        low = 0.0
        high = turn
        for _ in 0..<32 {
          let middle = (low + high) / 2
          if ordinate(middle) > level {
            low = middle
          } else {
            high = middle
          }
        }
        abscissa((low + high) / 2)
      } else {
        0.5
      }
      if horizontal >= inner && horizontal <= outer {
        return true
      }
    }
  }
  guard !self.stroke.is_empty() else { return false }
  let mut previous = (width / 2, height / 4)
  for segment in heart_path(width, height) {
    if segment is @layout.Cubic(ax, ay, bx, by, cx, cy) {
      if cubic_hit(previous, (ax, ay), (bx, by), (cx, cy), x, y, margin, 0) {
        return true
      }
      previous = (cx, cy)
    }
  }
  false
}
