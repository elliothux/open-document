///|
priv struct ShadowImage {
  key : String
  path : Array[@layout.PathSegment]
  bounds : @layout.Border
  alpha : Double
}

///|
priv struct OuterShadow {
  color : String
  alpha : Double
  blur : Double
  distance : Double
  direction : Double
  rotate : Bool
  alignment : String
  image : ShadowImage?
}

///|
fn outer_shadow(
  theme : Theme,
  list : Ref,
  placeholder : Ref?,
  scope : String,
) -> OuterShadow? raise @failure.Failure {
  let nodes = list.tree.children.get(list.node.id).unwrap_or([])
  guard list.node.attributes.is_empty() && list.node.text.trim().is_empty() else {
    @failure.reject(
      "unsupported-style",
      "Unsupported " + scope + " effect: effectLst",
    )
  }
  let inner = nodes.filter(n => n.name == "innerShdw")
  if !inner.is_empty() {
    guard inner is [node] &&
      node.uri == drawing_uri &&
      node.text.trim().is_empty() &&
      node.attributes.all(a => {
        a.uri.is_empty() && ["blurRad", "dist", "dir"].contains(a.name)
      }) &&
      !source_xml(list).contains("<!--") &&
      !source_xml(list).contains("<?") else {
      @failure.reject(
        "unsupported-style", "Extended inner shadow metadata is protected",
      )
    }
    for
      (name, high) in [
        ("blurRad", 2147483647.0),
        ("dist", 2147483647.0),
        ("dir", 21599999.0),
      ] {
      ignore(number(node.attribute(name).unwrap_or("0"), 0, high))
    }
    let reference : Ref = { tree: list.tree, node, }
    background_color_markup(reference)
    ignore(color_rgba(theme, reference, placeholder~))
  }
  // ONLYOFFICE retains innerShdw, while getOuterShdw alone supplies painted shadow resources.
  let nodes = nodes.filter(n => n.name != "innerShdw")
  if nodes.is_empty() {
    return None
  }
  guard nodes is [node] &&
    node.uri == drawing_uri &&
    node.name == "outerShdw" &&
    node.text.trim().is_empty() &&
    node.attributes.all(a => {
      a.uri.is_empty() &&
      ["blurRad", "dist", "dir", "sx", "sy", "kx", "ky", "algn", "rotWithShape"].contains(
        a.name,
      )
    }) else {
    @failure.reject(
      "unsupported-style",
      "Unsupported " + scope + " effect: effectLst",
    )
  }
  let values : Map[String, Double] = Map([])
  for
    (name, default, low, high) in [
      ("blurRad", "0", 0.0, 2147483647.0),
      ("dist", "0", 0.0, 2147483647.0),
      ("dir", "0", 0.0, 21599999.0),
      ("sx", "100000", -2147483648.0, 2147483647.0),
      ("sy", "100000", -2147483648.0, 2147483647.0),
      ("kx", "0", -5400000.0, 5400000.0),
      ("ky", "0", -5400000.0, 5400000.0),
    ] {
    values[name] = number(node.attribute(name).unwrap_or(default), low, high)
  }
  guard values["sx"] == 100000 &&
    values["sy"] == 100000 &&
    values["kx"] == 0 &&
    values["ky"] == 0 else {
    @failure.reject(
      "unsupported-style", "Scaled or skewed outer shadows require support",
    )
  }
  let alignment = node.attribute("algn").unwrap_or("b")
  guard ["tl", "t", "tr", "l", "ctr", "r", "bl", "b", "br"].contains(alignment) else {
    @failure.reject("unsupported-style", "Invalid outer shadow alignment")
  }
  let (color, alpha) = color_rgba(
    theme,
    { tree: list.tree, node, },
    placeholder~,
  )
  Some({
    color,
    alpha,
    blur: values["blurRad"] / 12700,
    distance: values["dist"] / 12700,
    direction: values["dir"] / 60000,
    rotate: flag(node, "rotWithShape", default=true),
    alignment,
    image: None,
  })
}

///|
fn check_flat_theme_3d(source : Ref) -> Unit raise @failure.Failure {
  let tree = source.tree
  let nodes = tree.children.get(source.node.id).unwrap_or([])
  let xml = source_xml(source)
  guard source.node.attributes.is_empty() &&
    source.node.text.trim().is_empty() &&
    !xml.contains("<!--") &&
    !xml.contains("<?") else {
    @failure.reject(
      "unsupported-style", "Extended theme 3D metadata is protected",
    )
  }
  if source.node.name == "scene3d" {
    guard nodes is [camera, light] &&
      camera.uri == drawing_uri &&
      camera.name == "camera" &&
      camera.attributes
      is [{ name: "prst", uri: "", value: "orthographicFront", .. }] &&
      camera.text.trim().is_empty() &&
      light.uri == drawing_uri &&
      light.name == "lightRig" &&
      light.text.trim().is_empty() &&
      light.attributes.length() == 2 &&
      light.attributes.all(a => {
        a.uri.is_empty() && ["rig", "dir"].contains(a.name)
      }) &&
      light.attribute("rig") == Some("threePt") &&
      [
        Some("t"),
        Some("tr"),
        Some("r"),
        Some("br"),
        Some("b"),
        Some("bl"),
        Some("l"),
        Some("tl"),
      ].contains(light.attribute("dir")) else {
      @failure.reject(
        "unsupported-style", "Nonflat or extended theme scene is protected",
      )
    }
    for item in [camera, light] {
      let rotations = tree.children.get(item.id).unwrap_or([])
      guard rotations.is_empty() ||
        (
          rotations is [rotation] &&
          rotation.uri == drawing_uri &&
          rotation.name == "rot" &&
          rotation.text.trim().is_empty() &&
          tree.children.get(rotation.id).unwrap_or([]).is_empty() &&
          rotation.attributes.length() == 3 &&
          rotation.attributes.all(a => {
            a.uri.is_empty() && ["lat", "lon", "rev"].contains(a.name)
          })
        ) else {
        @failure.reject(
          "unsupported-style", "Extended theme rotation is protected",
        )
      }
      if rotations.get(0) is Some(rotation) {
        for name in ["lat", "lon", "rev"] {
          let angle = number(rotation.attribute(name).unwrap(), 0, 21599999)
          guard item.name != "camera" || angle == 0 else {
            @failure.reject(
              "unsupported-style", "Nonflat theme camera is protected",
            )
          }
        }
      }
    }
  } else {
    guard source.node.name == "sp3d" &&
      (
        nodes.is_empty() ||
        (
          nodes is [bevel] &&
          bevel.uri == drawing_uri &&
          bevel.name == "bevelT" &&
          bevel.text.trim().is_empty() &&
          tree.children.get(bevel.id).unwrap_or([]).is_empty() &&
          bevel.attributes.all(a => {
            a.uri.is_empty() && ["w", "h", "prst"].contains(a.name)
          }) &&
          [None, Some("circle")].contains(bevel.attribute("prst"))
        )
      ) else {
      @failure.reject("unsupported-style", "Extended theme bevel is protected")
    }
    if nodes.get(0) is Some(bevel) {
      for name in ["w", "h"] {
        if bevel.attribute(name) is Some(value) {
          ignore(number(value, 0, 2147483647))
        }
      }
    }
  }
}

///|
fn read_outer_shadow(
  theme : Theme,
  source : Ref,
  chain : Array[Ref],
  properties : Array[Ref],
) -> OuterShadow? raise @failure.Failure {
  let mut direct = None
  let mut inherited = None
  for item in properties {
    for child in item.tree.children.get(item.node.id).unwrap_or([]) {
      if ["scene3d", "sp3d"].contains(child.name) {
        guard child.uri == drawing_uri &&
          item.tree.children
          .get(item.node.id)
          .unwrap_or([])
          .filter(n => n.name == child.name)
          .length() ==
          1 else {
          @failure.reject(
            "unsupported-style", "Extended or duplicate object 3D metadata is protected",
          )
        }
        // ONLYOFFICE ReadSpPr skips records5/6; preserve validated 3D without altering 2D drawing.
        check_object_3d(theme, { tree: item.tree, node: child, })
        continue
      }
      if child.name == "effectLst" {
        guard child.uri == drawing_uri &&
          item.tree.children
          .get(item.node.id)
          .unwrap_or([])
          .filter(n => n.name == "effectLst")
          .length() ==
          1 else {
          @failure.reject(
            "unsupported-style", "Extended or duplicate object effects are protected",
          )
        }
        let value = outer_shadow(
          theme,
          { tree: item.tree, node: child, },
          None,
          "object",
        )
        if value is Some(_) {
          if item.node.parent == source.node.id &&
            item.tree.part == source.tree.part {
            direct = value
          } else if inherited is None {
            inherited = value
          }
        }
      } else if child.uri == drawing_uri &&
        child.name == "effectDag" &&
        !item.tree.children.get(child.id).unwrap_or([]).is_empty() {
        @failure.reject(
          "unsupported-style",
          "Unsupported object effect: " + child.name,
        )
      }
    }
  }
  let mut themed = None
  if style_reference(theme, chain, "effect") is Some((effect, placeholder)) {
    let children = effect.tree.children.get(effect.node.id).unwrap_or([])
    for child in children {
      if child.uri == drawing_uri && ["scene3d", "sp3d"].contains(child.name) {
        guard children
          .filter(n => n.uri == drawing_uri && n.name == child.name)
          .length() ==
          1 &&
          effect.node.attributes.is_empty() &&
          effect.node.text.trim().is_empty() &&
          !source_xml(effect).contains("<!--") &&
          !source_xml(effect).contains("<?") else {
          @failure.reject(
            "unsupported-style", "Extended theme 3D style is protected",
          )
        }
        // ONLYOFFICE GetOuterShdw uses effectProperties; flat theme 3D stays metadata.
        check_flat_theme_3d({ tree: effect.tree, node: child, })
        continue
      }
      guard child.name == "effectLst" &&
        child.uri == drawing_uri &&
        children.filter(n => n.name == "effectLst").length() == 1 else {
        @failure.reject(
          "unsupported-style",
          "Unsupported theme effect: " + child.name,
        )
      }
      themed = outer_shadow(
        theme,
        { tree: effect.tree, node: child, },
        Some(placeholder),
        "theme",
      )
    }
  }
  if direct is Some(_) {
    direct
  } else if themed is Some(_) {
    themed
  } else {
    inherited
  }
}

///|
fn Object::with_shadow_image(self : Object) -> Object raise @failure.Failure {
  guard self.diagnostic.is_empty() &&
    self.shadow is Some(shadow) &&
    shadow.alpha > 0 &&
    self.geometry is Some(geometry) else {
    return self
  }
  guard ["shape", "image"].contains(self.kind) &&
    self.polyline.is_empty() &&
    self.preset != "line" else {
    @failure.reject(
      "unsupported-style", "Outer shadow requires a supported closed shape or picture",
    )
  }
  let alpha = if self.image is Some(_) {
    self.opacity
  } else if self.gradient is Some(gradient) {
    let stops = match gradient {
      Linear(stops, _, _) | Radial(stops) => stops
      _ => []
    }
    guard !stops.is_empty() && stops.all(s => s.opacity == stops[0].opacity) else {
      @failure.reject(
        "unsupported-style", "Outer shadow requires uniform fill opacity",
      )
    }
    stops[0].opacity
  } else if !self.has_fill() {
    if self.stroke.is_empty() || self.custom is Some({ stroke: false, .. }) {
      return self
    }
    self.stroke_alpha
  } else {
    self.fill_alpha
  }
  if alpha == 0 {
    return self
  }
  let pen = if !self.stroke.is_empty() &&
    !(self.custom is Some({ stroke: false, .. })) {
    self.line_width
  } else {
    0.0
  }
  let path = if !self.has_fill() {
    @layout.stroke_contour(
      self.shape_path(geometry),
      pen,
      self.cap,
      self.join,
      self.miter,
    )
  } else {
    self
    .shape_path({
      ..geometry,
      width: geometry.width + pen,
      height: geometry.height + pen,
    })
    .map(segment => {
      match segment {
        @layout.Move(x, y) => @layout.Move(x - pen / 2, y - pen / 2)
        @layout.Line(x, y) => @layout.Line(x - pen / 2, y - pen / 2)
        @layout.Cubic(a, b, c, d, x, y) =>
          @layout.Cubic(
            a - pen / 2,
            b - pen / 2,
            c - pen / 2,
            d - pen / 2,
            x - pen / 2,
            y - pen / 2,
          )
        @layout.Close => @layout.Close
      }
    })
  }
  let bounds = shadow_bounds(path, shadow.blur)
  let source = Json::array([
    Json(path),
    Json(shadow.color),
    Json(shadow.blur),
    Json(alpha * shadow.alpha),
  ]).stringify()
  let key = StringBuilder()
  key.write_string("#shadow:")
  for b in @crypto.sha256(@utf8.encode(source)) {
    key.write_string(b.to_int().to_string(radix=16).pad_start(2, '0'))
  }
  {
    ..self,
    shadow: Some({
      ..shadow,
      image: Some({
        key: key.to_string(),
        path,
        bounds,
        alpha: alpha * shadow.alpha,
      }),
    }),
  }
}

///|
fn OuterShadow::png(self : OuterShadow) -> Bytes raise @failure.Failure {
  let image = self.image.unwrap()
  let bytes = @image.encode_png(
    (image.bounds.width * 2).to_int(),
    (image.bounds.height * 2).to_int(),
    shadow_pixels(image, self),
  )
  guard bytes.length() <= 4194304 else {
    @failure.reject("limit-exceeded", "Outer shadow PNG exceeds image budget")
  }
  bytes
}

///|
fn Session::shadow_png(
  self : Session,
  key : String,
) -> Bytes raise @failure.Failure {
  if self.current().shadow(key) is Some(shadow) {
    return shadow.png()
  }
  for slide in self.slides {
    if slide.shadow(key) is Some(shadow) {
      return shadow.png()
    }
  }
  @failure.reject("invalid-image", "Unknown outer shadow resource")
}

///|
fn Slide::shadow(self : Slide, key : String) -> OuterShadow? {
  self.objects
  .iter()
  .filter_map(o => o.shadow)
  .find_first(shadow => {
    shadow.image.map(image => image.key == key).unwrap_or(false)
  })
}

///|
fn Object::shadow_primitive(
  self : Object,
  geometry : Geometry,
) -> @layout.PositionedPrimitive? raise @failure.Failure {
  guard self.diagnostic.is_empty() &&
    self.shadow is Some(shadow) &&
    shadow.image is Some(image) else {
    return None
  }
  let angle = shadow.direction * @math.PI / 180
  let dx = shadow.distance * @math.cos(angle)
  let dy = shadow.distance * @math.sin(angle)
  let (x, y) = if shadow.rotate {
    (dx, dy)
  } else {
    let inverse = geometry.matrix.inverse()
    (inverse.a * dx + inverse.c * dy, inverse.b * dx + inverse.d * dy)
  }
  Some(
    @layout.Image(
      {
        key: image.key,
        interpolate: Some(true),
        x: image.bounds.x + x,
        y: image.bounds.y + y,
        width: image.bounds.width,
        height: image.bounds.height,
      },
      1,
    ),
  )
}

///|
fn OuterShadow::markup(self : OuterShadow) -> String {
  "<a:effectLst xmlns:a='\{drawing_uri}'><a:outerShdw blurRad='\{(self.blur*12700).round().to_int64()}' dist='\{(self.distance*12700).round().to_int64()}' dir='\{(self.direction*60000).round().to_int64()}' algn='\{self.alignment}' rotWithShape='\{if self.rotate {1} else {0}}'><a:srgbClr val='\{self.color}'><a:alpha val='\{(self.alpha*100000).round().to_int64()}'/></a:srgbClr></a:outerShdw></a:effectLst>"
}
