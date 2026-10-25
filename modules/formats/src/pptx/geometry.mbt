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
  adjustments : (Double, Double, Double),
) -> Array[@layout.PathSegment] {
  if ["rect", "line", "ellipse"].contains(preset) {
    return @layout.basic_shape_path(preset, width, height)
  }
  if rounded_shape(preset) {
    return rounded_path(preset, width, height, adjustments)
  }
  if arrow_shape(preset) || polygon_shape(preset) {
    let path : Array[@layout.PathSegment] = []
    let points = if polygon_shape(preset) {
      polygon_points(preset, width, height, adjustments.0, second=adjustments.1)
    } else {
      arrow_points(preset, width, height, adjustments)
    }
    for i, (x, y) in points {
      path.push(if i == 0 { Move(x, y) } else { Line(x, y) })
    }
    path.push(Close)
    return path
  }
  [Move(0, 0), Line(width, 0), Line(width, height), Line(0, height), Close]
}

///|
fn native_transform_changes(
  object : Object,
  geometry : Geometry,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  if object.table is Some(_) {
    return table_transform_changes(object, geometry)
  }
  if object.chart is Some(_) {
    guard geometry.width >= 180 && geometry.height >= 150 else {
      @failure.reject(
        "invalid-transform", "Chart requires a frame of at least 180 x 150 points",
      )
    }
    let transform = object.source.child("xfrm", uri=presentation_uri).unwrap()
    // Ungrouping retains the inherited group orientation on the native frame.
    let changes = transform.pose_changes(object.geometry.unwrap(), geometry)
    for
      (node, values) in [
        (
          transform.child("off").unwrap(),
          [("x", geometry.x), ("y", geometry.y)],
        ),
        (
          transform.child("ext").unwrap(),
          [("cx", geometry.width), ("cy", geometry.height)],
        ),
      ] {
      for (name, value) in values {
        let text = (value * 12700).round().to_int64().to_string()
        if node.node.attribute(name) != Some(text) {
          changes.push(attribute_change(node, name, text))
        }
      }
    }
    return changes
  }
  let properties = object.source
    .child(
      if object.kind == "group" {
        "grpSpPr"
      } else {
        "spPr"
      },
      uri=presentation_uri,
    )
    .unwrap_or_error(
      @failure.Failure(
        code="protected-content",
        part=object.source.tree.part,
        offset=-1,
        message="Missing editable shape properties",
      ),
    )
  let transform = properties.child("xfrm")
  let changes : Array[@xml.SourceChange] = []
  let off = "<a:off xmlns:a=\"\{drawing_uri}\" x=\"\{(geometry.x * 12700).round().to_int64()}\" y=\"\{(geometry.y * 12700).round().to_int64()}\"/>"
  let ext = "<a:ext xmlns:a=\"\{drawing_uri}\" cx=\"\{(geometry.width * 12700).round().to_int64()}\" cy=\"\{(geometry.height * 12700).round().to_int64()}\"/>"
  if transform is Some(transform) {
    changes.append(transform.pose_changes(object.geometry.unwrap(), geometry))
    let missing = StringBuilder()
    for (name, xml) in [("off", off), ("ext", ext)] {
      if transform.child(name) is Some(item) {
        for
          (key, value) in (if name == "off" {
            [("x", geometry.x), ("y", geometry.y)]
          } else {
            [("cx", geometry.width), ("cy", geometry.height)]
          }) {
          let attr = item.node.attributes
            .iter()
            .find_first(attr => attr.uri.is_empty() && attr.name == key)
          guard attr is Some(attr) else {
            @failure.reject("malformed-pptx", "Incomplete transform attribute")
          }
          changes.push({
            node: item.node.id,
            offset: attr.start - item.node.start,
            length: attr.end - attr.start,
            xml: (value * 12700).round().to_int64().to_string(),
          })
        }
      } else {
        missing.write_string(xml)
      }
    }
    if !missing.to_string().is_empty() {
      changes.push(insertion(transform.node, missing.to_string()))
    }
  } else {
    let xml = "<a:xfrm xmlns:a=\"\{drawing_uri}\" rot=\"\{(geometry.rotation * 60000).round().to_int64()}\" flipH=\"\{if geometry.flip_x { 1 } else { 0 }}\" flipV=\"\{if geometry.flip_y { 1 } else { 0 }}\">\{off}\{ext}</a:xfrm>"
    // xfrm is the first spPr child, before geometry and paint declarations.
    if properties.node.empty {
      changes.push(insertion(properties.node, xml))
    } else {
      changes.push({
        node: properties.node.id,
        offset: properties.node.opening_end - properties.node.start,
        length: 0,
        xml,
      })
    }
  }
  changes
}
