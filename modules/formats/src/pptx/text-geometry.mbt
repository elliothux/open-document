///|
fn TextGeometry::line_matrix(
  self : TextGeometry,
  line : @layout.Line,
) -> @layout.Matrix {
  self.matrix.then(
    self.transforms.get(line.paragraph).unwrap_or(@layout.Matrix::identity()),
  )
}

///|
fn TextGeometry::line_rect(
  self : TextGeometry,
  line : @layout.Line,
  rect : @layout.Border,
) -> @layout.Border? {
  let rect : @layout.Border = if self.transforms.get(line.paragraph)
    is Some(matrix) {
    // Cell directions are quarter turns, so opposite corners bound the transformed rectangle.
    let (x, y) = matrix.point(rect.x, rect.y)
    let (right, bottom) = matrix.point(
      rect.x + rect.width,
      rect.y + rect.height,
    )
    {
      x: x.min(right),
      y: y.min(bottom),
      width: (right - x).abs(),
      height: (bottom - y).abs(),
    }
  } else {
    rect
  }
  guard line.cellClip is Some(clip) else { return Some(rect) }
  let x = rect.x.max(clip.x)
  let y = rect.y.max(clip.y)
  let right = (rect.x + rect.width).min(clip.x + clip.width)
  let bottom = (rect.y + rect.height).min(clip.y + clip.height)
  if right > x && bottom > y {
    Some({ x, y, width: right - x, height: bottom - y, })
  } else {
    None
  }
}
