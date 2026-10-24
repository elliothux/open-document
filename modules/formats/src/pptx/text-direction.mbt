///|
fn Object::text_plane(
  self : Object,
  geometry : Geometry,
) -> (Body, Geometry, @layout.Matrix) raise @failure.Failure {
  let body = self.shape_body(geometry)
  let (body, geometry, upright) = if body.upright {
    self.upright_plane(body, geometry)
  } else {
    (body, geometry, @layout.Matrix::identity())
  }
  match body.direction {
    "vert" =>
      (
        {
          ..body,
          left: body.top,
          right: body.bottom,
          top: body.right,
          bottom: body.left,
        },
        { ..geometry, width: geometry.height, height: geometry.width, },
        upright.then({ a: 0, b: 1, c: -1, d: 0, e: geometry.width, f: 0, }),
      )
    "vert270" =>
      (
        {
          ..body,
          left: body.bottom,
          right: body.top,
          top: body.left,
          bottom: body.right,
        },
        { ..geometry, width: geometry.height, height: geometry.width, },
        upright.then({ a: 0, b: -1, c: 1, d: 0, e: 0, f: geometry.height, }),
      )
    _ => (body, geometry, upright)
  }
}

///|
fn Body::rotated_text(self : Body) -> Bool {
  ["vert", "vert270"].contains(self.direction)
}

///|
fn Body::text_rotation(
  self : Body,
  width : Double,
  height : Double,
  offset : Double,
) -> @layout.Matrix {
  if self.rotation % 360 == 0 {
    return @layout.Matrix::identity()
  }
  let radians = self.rotation % 360 * @math.PI / 180
  let a = @math.cos(radians)
  let b = @math.sin(radians)
  let x = (self.left + width - self.right) / 2
  let y = self.top + offset + (height - self.top - self.bottom) / 2
  // ONLYOFFICE rotates around the measured content rectangle before applying its anchor and frame direction.
  { a, b, c: -b, d: a, e: x - a * x + b * y, f: y - b * x - a * y, }
}

///|
fn Object::text_extent(
  self : Object,
  geometry : Geometry,
  value : Double,
  horizontal~ : Bool,
) -> Geometry raise @failure.Failure {
  let rotated = self.body.rotated_text() !=
    (self.body.upright && self.upright_swaps_axes(geometry))
  if horizontal != rotated {
    { ..geometry, width: value, }
  } else {
    { ..geometry, height: value, }
  }
}
