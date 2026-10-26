///|
fn donut_path(
  width : Double,
  height : Double,
  adjustment : Double,
) -> Array[@layout.PathSegment] {
  let path = @layout.basic_shape_path("ellipse", width, height)
  let inset = width.min(height) * adjustment.clamp(min=0, max=0.5)
  let x = width / 2
  let y = height / 2
  let rx = x - inset
  let ry = y - inset
  let k = 0.5522847498307936
  // Opposite winding retains the native hole for fill and image clipping.
  path.append([
    Move(inset, y),
    Cubic(inset, y + k * ry, x - k * rx, height - inset, x, height - inset),
    Cubic(
      x + k * rx,
      height - inset,
      width - inset,
      y + k * ry,
      width - inset,
      y,
    ),
    Cubic(width - inset, y - k * ry, x + k * rx, inset, x, inset),
    Cubic(x - k * rx, inset, inset, y - k * ry, inset, y),
    Close,
  ])
  path
}

///|
fn Object::donut_hit(
  self : Object,
  width : Double,
  height : Double,
  x : Double,
  y : Double,
  margin : Double,
) -> Bool {
  guard width > 0 && height > 0 else { return false }
  if !self.text().is_empty() {
    let body = self.shape_body(self.geometry.unwrap())
    if x >= body.left &&
      x <= width - body.right &&
      y >= body.top &&
      y <= height - body.bottom {
      return true
    }
  }
  let dx = x - width / 2
  let dy = y - height / 2
  let radius_x = width / 2
  let radius_y = height / 2
  let inset = width.min(height) * self.adjustments.0.clamp(min=0, max=0.5)
  let inner_x = radius_x - inset
  let inner_y = radius_y - inset
  let ellipse = fn(rx : Double, ry : Double) {
    dx * dx / (rx * rx) + dy * dy / (ry * ry)
  }
  if self.has_fill() &&
    ellipse(radius_x, radius_y) <= 1 &&
    (inner_x <= 0 || inner_y <= 0 || ellipse(inner_x, inner_y) >= 1) {
    return true
  }
  guard !self.stroke.is_empty() else { return false }
  let mut previous = (0.0, 0.0)
  for segment in donut_path(width, height, self.adjustments.0) {
    match segment {
      Move(x, y) => previous = (x, y)
      Cubic(ax, ay, bx, by, cx, cy) => {
        if cubic_hit(previous, (ax, ay), (bx, by), (cx, cy), x, y, margin, 0) {
          return true
        }
        previous = (cx, cy)
      }
      _ => ()
    }
  }
  false
}
