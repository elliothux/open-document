///|
fn Object::text_full_angle(
  self : Object,
  geometry : Geometry,
) -> Double raise @failure.Failure {
  let mut angle = geometry.rotation
  for parent = self.source.node.parent
      parent >= 0
      parent = self.source.tree.nodes[parent].parent {
    let node = self.source.tree.nodes[parent]
    if node.name == "grpSp" && node.uri == presentation_uri {
      let group : Ref = { tree: self.source.tree, node, }
      let transform = group
        .child("grpSpPr", uri=presentation_uri)
        .bind(properties => properties.child("xfrm"))
      angle += number(
          transform.bind(value => value.node.attribute("rot")).unwrap_or("0"),
          -21600000,
          21600000,
        ) /
        60000
    }
  }
  (angle % 360 + 360) % 360
}

///|
fn Object::upright_swaps_axes(
  self : Object,
  geometry : Geometry,
) -> Bool raise @failure.Failure {
  let angle = self.text_full_angle(geometry)
  (angle >= 45 && angle < 135) || (angle >= 225 && angle < 315)
}

///|
fn Object::upright_plane(
  self : Object,
  body : Body,
  geometry : Geometry,
) -> (Body, Geometry, @layout.Matrix) raise @failure.Failure {
  let matrix = geometry.matrix
  let angle = self.text_full_angle(geometry) * @math.PI / 180
  let flip_x = @math.cos(angle) * matrix.a + @math.sin(angle) * matrix.b < 0
  let flip_y = -@math.sin(angle) * matrix.c + @math.cos(angle) * matrix.d < 0
  let (cx, cy) = matrix.point(geometry.width / 2, geometry.height / 2)
  let x = cx + (body.left - body.right) / 2 * (if flip_x { -1.0 } else { 1.0 })
  let y = cy + (body.top - body.bottom) / 2 * (if flip_y { -1.0 } else { 1.0 })
  let (body, frame) = if self.upright_swaps_axes(geometry) {
    (
      {
        ..body,
        left: body.top,
        top: body.left,
        right: body.bottom,
        bottom: body.right,
      },
      { ..geometry, width: geometry.height, height: geometry.width, },
    )
  } else {
    (body, geometry)
  }
  // ONLYOFFICE keeps the text rectangle's inset offset in page axes, with full flips applied.
  let origin = {
    ..@layout.Matrix::identity(),
    e: x - (body.left + frame.width - body.right) / 2,
    f: y - (body.top + frame.height - body.bottom) / 2,
  }
  (body, frame, matrix.inverse().then(origin))
}

///|
fn Object::text_clip(
  self : Object,
  geometry : Geometry,
) -> (@layout.Matrix, @layout.Border) raise @failure.Failure {
  if !self.body.upright {
    return (
      @layout.Matrix::identity(),
      { x: 0, y: 0, width: geometry.width, height: geometry.height, },
    )
  }
  let (width, height) = if self.upright_swaps_axes(geometry) {
    (geometry.height, geometry.width)
  } else {
    (geometry.width, geometry.height)
  }
  let (cx, cy) = geometry.matrix.point(geometry.width / 2, geometry.height / 2)
  (
    geometry.matrix
    .inverse()
    .then({
      ..@layout.Matrix::identity(),
      e: cx - width / 2,
      f: cy - height / 2,
    }),
    { x: 0, y: 0, width, height, },
  )
}
