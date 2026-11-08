///|
fn callout_path(
  width : Double,
  height : Double,
  adjustments : (Double, Double, Double),
) -> Array[@layout.PathSegment] {
  guard width > 0 && height > 0 else { return [] }
  let dx = adjustments.0 * width
  let dy = adjustments.1 * height
  let x = width / 2 + dx
  let y = height / 2 + dy
  let vertical = adjustments.1.abs() > adjustments.0.abs()
  let x1 = width * (if dx > 0 { 7.0 } else { 2.0 }) / 12
  let x2 = width * (if dx > 0 { 10.0 } else { 5.0 }) / 12
  let y1 = height * (if dy > 0 { 7.0 } else { 2.0 }) / 12
  let y2 = height * (if dy > 0 { 10.0 } else { 5.0 }) / 12
  let top = if vertical && dy <= 0 { (x, y.min(0)) } else { (x1, 0.0) }
  let right = if !vertical && dx > 0 { (x.max(width), y) } else { (width, y1) }
  let bottom = if vertical && dy > 0 {
    (x, y.max(height))
  } else {
    (x1, height)
  }
  let left = if !vertical && dx <= 0 { (x.min(0), y) } else { (0.0, y1) }
  let radius = width.min(height) * adjustments.2
  let inset = radius * (1 - (7.0.sqrt() - 1) / 3)
  let path : Array[@layout.PathSegment] = [Move(0, radius)]
  if radius > 0 {
    path.push(Cubic(0, inset, inset, 0, radius, 0))
  }
  path.append([
    Line(x1, 0),
    Line(top.0, top.1),
    Line(x2, 0),
    Line(width - radius, 0),
  ])
  if radius > 0 {
    path.push(Cubic(width - inset, 0, width, inset, width, radius))
  }
  path.append([
    Line(width, y1),
    Line(right.0, right.1),
    Line(width, y2),
    Line(width, height - radius),
  ])
  if radius > 0 {
    path.push(
      Cubic(
        width,
        height - inset,
        width - inset,
        height,
        width - radius,
        height,
      ),
    )
  }
  path.append([
    Line(x2, height),
    Line(bottom.0, bottom.1),
    Line(x1, height),
    Line(radius, height),
  ])
  if radius > 0 {
    path.push(Cubic(inset, height, 0, height - inset, 0, height - radius))
  }
  path.append([Line(0, y2), Line(left.0, left.1), Line(0, y1), Close])
  path
}

///|
fn Object::fill_bounds(
  self : Object,
  geometry : Geometry,
) -> @layout.Border raise @failure.Failure {
  let frame : @layout.Border = {
    x: 0,
    y: 0,
    width: geometry.width,
    height: geometry.height,
  }
  guard self.preset == "wedgeRoundRectCallout" || self.custom is Some(_) else {
    return frame
  }
  let mut left = 0.0
  let mut top = 0.0
  let mut right = geometry.width
  let mut bottom = geometry.height
  for segment in self.shape_path(geometry) {
    let points = match segment {
      @layout.Move(x, y) | @layout.Line(x, y) => [(x, y)]
      @layout.Cubic(a, b, c, d, x, y) => [(a, b), (c, d), (x, y)]
      @layout.Close => []
    }
    for (x, y) in points {
      left = left.min(x)
      top = top.min(y)
      right = right.max(x)
      bottom = bottom.max(y)
    }
  }
  { x: left, y: top, width: right - left, height: bottom - top, }
}

///|
fn Object::callout_hit(
  self : Object,
  geometry : Geometry,
  x : Double,
  y : Double,
  margin : Double,
) -> Bool {
  path_hit(
    callout_path(geometry.width, geometry.height, self.adjustments),
    self.has_fill(),
    !self.stroke.is_empty(),
    x,
    y,
    margin,
  )
}
