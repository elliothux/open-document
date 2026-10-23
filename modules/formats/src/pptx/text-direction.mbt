///|
fn Object::text_plane(
  self : Object,
  geometry : Geometry,
) -> (Body, Geometry, @layout.Matrix) {
  let body = self.shape_body(geometry)
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
        { a: 0, b: 1, c: -1, d: 0, e: geometry.width, f: 0, },
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
        { a: 0, b: -1, c: 1, d: 0, e: 0, f: geometry.height, },
      )
    _ => (body, geometry, @layout.Matrix::identity())
  }
}

///|
fn Body::rotated_text(self : Body) -> Bool {
  ["vert", "vert270"].contains(self.direction)
}

///|
fn Object::text_extent(
  self : Object,
  geometry : Geometry,
  value : Double,
  horizontal~ : Bool,
) -> Geometry {
  if horizontal != self.body.rotated_text() {
    { ..geometry, width: value, }
  } else {
    { ..geometry, height: value, }
  }
}
