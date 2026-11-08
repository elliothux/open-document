///|
priv struct BarProjection {
  frame : (Double, Double)
  plot : @layout.Border
  aspect : Double
  depth : Double
  rotation : (Double, Double)
  focal : Double
  camera : (Double, Double, Double)
}

///|
fn bar_rotate(
  point : (Double, Double, Double),
  angles : (Double, Double),
) -> (Double, Double, Double) {
  let (x, y, z) = point
  let (sx, cx) = (@math.sin(angles.0), @math.cos(angles.0))
  let (sy, cy) = (@math.sin(angles.1), @math.cos(angles.1))
  (
    z * sy + x * cy,
    x * sx * sy + y * cx - z * sx * cy,
    -x * sy * cx + y * sx + z * cy * cx,
  )
}

///|
fn BarProjection::rotate(
  self : BarProjection,
  x : Double,
  y : Double,
  z : Double,
) -> (Double, Double, Double) {
  bar_rotate(
    ((x - self.frame.0 / 2) / self.aspect, y - self.frame.1 / 2, z),
    self.rotation,
  )
}

///|
fn BarProjection::point(
  self : BarProjection,
  x : Double,
  y : Double,
  z : Double,
) -> (Double, Double, Double) {
  if self.focal == 0 {
    return (x, y, z)
  }
  let (x, y, z) = self.rotate(x, y, z)
  let factor = self.focal / (z + self.camera.2 + self.focal)
  (
    self.plot.x + self.plot.width / 2 + (x + self.camera.0) * factor,
    self.plot.y + self.plot.height / 2 + (y + self.camera.1) * factor,
    z,
  )
}

///|
fn bar_camera_axis(
  points : Array[(Double, Double, Double)],
  focal : Double,
  depth : Double,
  vertical : Bool,
) -> (Double, Double) raise @failure.Failure {
  let coordinate = fn(point : (Double, Double, Double)) {
    if vertical {
      point.1
    } else {
      point.0
    }
  }
  for first in 0..<points.length() {
    for last in (first + 1)..<points.length() {
      let a = points[first]
      let b = points[last]
      let da = a.2 + depth + focal
      let db = b.2 + depth + focal
      guard da > 0 && db > 0 else {
        @failure.reject(
          "layout-overflow", "Three-dimensional camera intersects the plot",
        )
      }
      let shift = -(coordinate(a) * db + coordinate(b) * da) / (da + db)
      let left = (coordinate(a) + shift) * focal / da
      let right = (coordinate(b) + shift) * focal / db
      let low = left.min(right)
      let high = left.max(right)
      if points.all(p => {
          let value = (coordinate(p) + shift) * focal / (p.2 + depth + focal)
          value >= low - 1.0e-8 && value <= high + 1.0e-8
        }) {
        return (shift, high - low)
      }
    }
  }
  @failure.reject(
    "layout-overflow", "Three-dimensional camera cannot center the plot",
  )
}

///|
fn bar_projection(
  frame : (Double, Double),
  plot : @layout.Border,
  rotation : (Double, Double),
  perspective : Double,
  percent : Double,
  series : Int32,
  categories : Int32,
  height_percent? : Double,
) -> BarProjection raise @failure.Failure {
  let angles = (rotation.0 * @math.PI / 180, rotation.1 * @math.PI / 180)
  if perspective == 0 {
    return {
      frame,
      plot,
      aspect: 1,
      depth: 0,
      rotation: angles,
      focal: 0,
      camera: (0, 0, 0),
    }
  }
  // ONLYOFFICE standard columns distribute categories along X and series along depth.
  let aspect = ((series + categories) / 2).max(1).to_double() /
    categories.to_double() *
    height_percent
    .map(percent => plot.width * percent / plot.height)
    .unwrap_or(1)
  let amount = percent * series.to_double() / categories.to_double()
  let depth_width = height_percent
    .map(percent => plot.height / percent)
    .unwrap_or(plot.width)
  let depth = depth_width * amount * 2 / (1 + amount)
  let focal = (
      plot.height / 2 + (plot.y - (frame.1 - plot.y - plot.height)).abs()
    ) /
    @math.tan(perspective * @math.PI / 720)
  let base : BarProjection = {
    frame,
    plot,
    aspect,
    depth,
    rotation: angles,
    focal,
    camera: (0, 0, 0),
  }
  let corners : Array[(Double, Double, Double)] = []
  for x in [plot.x, plot.x + plot.width] {
    for y in [plot.y, plot.y + plot.height] {
      for z in [0.0, depth] {
        corners.push((x, y, z))
      }
    }
  }
  let points = corners.map(p => base.rotate(p.0, p.1, p.2))
  let mut camera_z = -corners
    .map(p => {
      bar_rotate(
        (
          (p.0 - frame.0 / 2) / (plot.width / plot.height),
          p.1 - frame.1 / 2,
          p.2,
        ),
        angles,
      ).2
    })
    .fold(init=1.0e100, (a, b) => a.min(b))
  let mut camera_x = 0.0
  let mut camera_y = 0.0
  let mut iterations = 0
  // Native camera fitting refines at 100, 10 and 1 logical pixels, with a bounded search.
  for step in [75.0, 7.5, 0.75] {
    let measure = fn() raise @failure.Failure {
      let (x, width) = bar_camera_axis(points, focal, camera_z, false)
      let (y, height) = bar_camera_axis(points, focal, camera_z, true)
      camera_x = x
      camera_y = y
      (width, height)
    }
    let mut extent = measure()
    let inside = extent.0 < plot.width && extent.1 < plot.height
    while (if inside {
            extent.0 < plot.width && extent.1 < plot.height
          } else {
            extent.0 > plot.width || extent.1 > plot.height
          }) {
      guard iterations < 1000 else {
        @failure.reject(
          "limit-exceeded", "Three-dimensional camera fitting exceeds budget",
        )
      }
      camera_z += if inside { -step } else { step }
      extent = measure()
      iterations += 1
    }
  }
  { ..base, camera: (camera_x, camera_y, camera_z), }
}

///|
fn bar_polygon(
  points : Array[(Double, Double, Double)],
  fill : String,
  pen : (String, Double),
) -> @layout.PositionedPrimitive {
  let path : Array[@layout.PathSegment] = points.mapi((i, point) => {
    if i == 0 {
      Move(point.0, point.1)
    } else {
      Line(point.0, point.1)
    }
  })
  // Native faces repeat the first vertex while retaining butt caps at the stroke endpoints.
  path.push(Line(points[0].0, points[0].1))
  line_path(path, pen, fill~, miter=10)
}
