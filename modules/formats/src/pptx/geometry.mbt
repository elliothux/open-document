///|
fn object_matrix(
  x : Double,
  y : Double,
  width : Double,
  height : Double,
  rotation : Double,
  flip_x : Bool,
  flip_y : Bool,
) -> @layout.Matrix {
  let angle = rotation * @math.PI / 180
  let sx = if flip_x { -1.0 } else { 1.0 }
  let sy = if flip_y { -1.0 } else { 1.0 }
  let a = @math.cos(angle) * sx
  let b = @math.sin(angle) * sx
  let c = -@math.sin(angle) * sy
  let d = @math.cos(angle) * sy
  {
    a,
    b,
    c,
    d,
    e: x + width / 2 - a * width / 2 - c * height / 2,
    f: y + height / 2 - b * width / 2 - d * height / 2,
  }
}

///|
fn geometry(
  chain : Array[Ref],
  parent : @layout.Matrix,
  group : Bool,
) -> Geometry? raise @failure.Failure {
  let properties = children(
    chain,
    if group {
      "grpSpPr"
    } else {
      "spPr"
    },
    uri=presentation_uri,
  )
  let transforms = children(properties, "xfrm")
  if transforms.is_empty() {
    return None
  }
  let off = children(transforms, "off")
  let ext = children(transforms, "ext")
  guard attribute(off, "x") is Some(x) &&
    attribute(off, "y") is Some(y) &&
    attribute(ext, "cx") is Some(width) &&
    attribute(ext, "cy") is Some(height) else {
    @failure.reject("malformed-pptx", "Incomplete object geometry")
  }
  let x = number(x, -182880000, 182880000) / 12700
  let y = number(y, -182880000, 182880000) / 12700
  let width = number(width, if group { 1 } else { 0 }, 182880000) / 12700
  let height = number(height, if group { 1 } else { 0 }, 182880000) / 12700
  let rotation = number(
      attribute(transforms, "rot").unwrap_or("0"),
      -21600000,
      21600000,
    ) /
    60000
  let flip_x = ["1", "true"].contains(
    attribute(transforms, "flipH").unwrap_or("0"),
  )
  let flip_y = ["1", "true"].contains(
    attribute(transforms, "flipV").unwrap_or("0"),
  )
  Some(
    geometry_in_parent(x, y, width, height, rotation, flip_x, flip_y, parent),
  )
}

///|
fn geometry_in_parent(
  x : Double,
  y : Double,
  width : Double,
  height : Double,
  rotation : Double,
  flip_x : Bool,
  flip_y : Bool,
  parent : @layout.Matrix,
) -> Geometry raise @failure.Failure {
  let sx = (parent.a * parent.a + parent.b * parent.b).sqrt()
  let sy = (parent.c * parent.c + parent.d * parent.d).sqrt()
  ignore(parent.inverse())
  let x = x * sx
  let y = y * sy
  let width = width * sx
  let height = height * sy
  // Group scale changes the frame, not the font, margins or pen width.
  let matrix = {
    ..parent,
    a: parent.a / sx,
    b: parent.b / sx,
    c: parent.c / sy,
    d: parent.d / sy,
  }.then(object_matrix(x, y, width, height, rotation, flip_x, flip_y))
  ignore(matrix.inverse())
  { x, y, width, height, rotation, flip_x, flip_y, matrix, }
}

///|
fn group_matrix(
  source : Ref,
  geometry : Geometry,
) -> @layout.Matrix raise @failure.Failure {
  let transform = source
    .child("grpSpPr", uri=presentation_uri)
    .bind(item => item.child("xfrm"))
  guard transform is Some(transform) else {
    @failure.reject("malformed-pptx", "Missing group transform")
  }
  let off = transform.child("chOff")
  let ext = transform.child("chExt")
  let x = number(
      off.bind(item => item.node.attribute("x")).unwrap_or("0"),
      -182880000,
      182880000,
    ) /
    12700
  let y = number(
      off.bind(item => item.node.attribute("y")).unwrap_or("0"),
      -182880000,
      182880000,
    ) /
    12700
  let width = number(
      ext.bind(item => item.node.attribute("cx")).unwrap_or("0"),
      1,
      182880000,
    ) /
    12700
  let height = number(
      ext.bind(item => item.node.attribute("cy")).unwrap_or("0"),
      1,
      182880000,
    ) /
    12700
  let sx = geometry.width / width
  let sy = geometry.height / height
  let matrix = geometry.matrix.then({
    a: sx,
    b: 0,
    c: 0,
    d: sy,
    e: -x * sx,
    f: -y * sy,
  })
  ignore(matrix.inverse())
  matrix
}

///|
fn shape_path(
  preset : String,
  width : Double,
  height : Double,
  adjustments : (Double, Double),
) -> Array[@layout.PathSegment] {
  if preset == "line" {
    return [Move(0, 0), Line(width, height)]
  }
  if preset == "ellipse" {
    let k = 0.5522847498307936
    let x = width / 2
    let y = height / 2
    return [
      Move(width, y),
      Cubic(width, y + k * y, x + k * x, height, x, height),
      Cubic(x - k * x, height, 0, y + k * y, 0, y),
      Cubic(0, y - k * y, x - k * x, 0, x, 0),
      Cubic(x + k * x, 0, width, y - k * y, width, y),
      Close,
    ]
  }
  if preset == "roundRect" {
    let r = width.min(height) * adjustments.0.max(0).min(0.5)
    let k = 0.5522847498307936 * r
    return [
      Move(r, 0),
      Line(width - r, 0),
      Cubic(width - r + k, 0, width, r - k, width, r),
      Line(width, height - r),
      Cubic(width, height - r + k, width - r + k, height, width - r, height),
      Line(r, height),
      Cubic(r - k, height, 0, height - r + k, 0, height - r),
      Line(0, r),
      Cubic(0, r - k, r - k, 0, r, 0),
      Close,
    ]
  }
  if arrow_shape(preset) {
    let path : Array[@layout.PathSegment] = []
    for i, (x, y) in arrow_points(preset, width, height, adjustments) {
      path.push(if i == 0 { Move(x, y) } else { Line(x, y) })
    }
    path.push(Close)
    return path
  }
  [Move(0, 0), Line(width, 0), Line(width, height), Line(0, height), Close]
}
