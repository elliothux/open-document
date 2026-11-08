///|
fn Object::polyline_hit(
  self : Object,
  geometry : Geometry,
  x : Double,
  y : Double,
  margin : Double,
) -> Bool {
  if self.stroke.is_empty() {
    return false
  }
  for index in 1..<self.polyline.length() {
    let (ax, ay) = self.polyline[index - 1]
    let (bx, by) = self.polyline[index]
    let ax = ax * geometry.width
    let ay = ay * geometry.height
    let dx = bx * geometry.width - ax
    let dy = by * geometry.height - ay
    let square = dx * dx + dy * dy
    let t = (if square > 0 {
        ((x - ax) * dx + (y - ay) * dy) / square
      } else {
        0.0
      })
      .max(0)
      .min(1)
    let gx = x - ax - t * dx
    let gy = y - ay - t * dy
    if gx * gx + gy * gy <= margin * margin {
      return true
    }
  }
  false
}
