///|
fn WordTree::drawing_child(
  self : WordTree,
  parent : Int,
  name : String,
  uri~ : String = picture_drawing_uri,
) -> Int? {
  self.children[parent]
  .iter()
  .find_first(id => self.nodes[id].uri == uri && self.nodes[id].name == name)
}

///|
fn WordTree::shape_children(
  self : WordTree,
  parent : Int,
  names : Array[String],
  uri~ : String = picture_drawing_uri,
) -> Unit raise @failure.Failure {
  let seen : Map[String, Unit] = Map([])
  guard self.nodes[parent].text.trim().is_empty() else {
    @failure.reject("unsupported-layout", "Unknown shape text content")
  }
  for child in self.children[parent] {
    let node = self.nodes[child]
    guard node.uri == uri &&
      names.contains(node.name) &&
      !seen.contains(node.name) else {
      @failure.reject(
        "unsupported-layout", "Unknown or duplicate shape content",
      )
    }
    seen[node.name] = ()
  }
}

///|
fn WordTree::shape_rgb(
  self : WordTree,
  parent : Int,
  alpha~ : Bool = false,
) -> String raise @failure.Failure {
  let no_fill = self.drawing_child(parent, "noFill")
  let solid = self.drawing_child(parent, "solidFill")
  guard no_fill is None || solid is None else {
    @failure.reject("unsupported-layout", "Conflicting shape fills")
  }
  if no_fill is Some(id) {
    self.shape_children(id, [])
    guard self.nodes[id].attributes.is_empty() else {
      @failure.reject("unsupported-layout", "Unknown shape no-fill attributes")
    }
    return ""
  }
  guard solid is Some(id) else { return "" }
  self.shape_children(id, ["srgbClr"])
  guard self.children[id] is [color] && self.nodes[id].attributes.is_empty() else {
    @failure.reject(
      "unsupported-layout", "Shape color requires an explicit RGB fill",
    )
  }
  self.shape_children(color, if alpha { ["alpha"] } else { [] })
  let node = self.nodes[color]
  let rgb = node.attribute("val").unwrap_or("")
  guard node.attributes.all(a => a.uri.is_empty() && a.name == "val") &&
    rgb.length() == 6 &&
    rgb.iter().all(ch => ch.is_ascii_hexdigit()) else {
    @failure.reject("unsupported-layout", "Invalid shape RGB color")
  }
  rgb
}

///|
fn WordTree::read_basic_shape(
  self : WordTree,
  drawing : Int,
  data : Int,
) -> @layout.DrawingFrame raise @failure.Failure {
  guard self.nodes[data].attributes.all(a => a.uri.is_empty() && a.name == "uri") &&
    self.children[data] is [shape] &&
    self.nodes[shape].uri == word_shape_uri &&
    self.nodes[shape].name == "wsp" &&
    self.nodes[shape].attributes.is_empty() else {
    @failure.reject(
      "unsupported-layout", "Drawing requires an ordinary WordprocessingShape",
    )
  }
  self.shape_children(
    shape,
    ["cNvPr", "cNvSpPr", "spPr", "bodyPr", "txbx"],
    uri=word_shape_uri,
  )
  let frame = self.drawing_data(drawing).0
  let identity = self.nodes[self.anchor_child(frame.id, "docPr")]
  guard !["1", "true"].contains(identity.attribute("hidden").unwrap_or("0")) else {
    @failure.reject(
      "unsupported-layout", "Hidden shapes require layout support",
    )
  }
  if self.drawing_child(shape, "bodyPr", uri=word_shape_uri) is Some(body) {
    self.shape_children(body, [
      "prstTxWarp", "noAutofit", "normAutofit", "spAutoFit",
    ])
    for child in self.children[body] {
      if self.nodes[child].name == "prstTxWarp" {
        guard self.nodes[child].attribute("prst") == Some("textNoShape") else {
          @failure.reject(
            "unsupported-layout", "Shape text warp requires support",
          )
        }
        self.shape_children(child, ["avLst"])
        if self.drawing_child(child, "avLst") is Some(list) {
          self.shape_children(list, [])
        }
      } else {
        self.shape_children(child, [])
      }
    }
  }
  let (width, height, anchor) = self.drawing_geometry(drawing)
  if self.drawing_child(shape, "cNvPr", uri=word_shape_uri) is Some(id) {
    self.shape_children(id, [])
    guard !["1", "true"].contains(
        self.nodes[id].attribute("hidden").unwrap_or("0"),
      ) &&
      self.nodes[id].attributes.all(a => {
        a.uri.is_empty() &&
        ["id", "name", "descr", "title", "hidden"].contains(a.name)
      }) else {
      @failure.reject(
        "unsupported-layout", "Hidden or extended shape metadata requires support",
      )
    }
  }
  if self.drawing_child(shape, "cNvSpPr", uri=word_shape_uri) is Some(id) {
    guard self.nodes[id].attributes.all(a => {
      a.uri.is_empty() &&
      a.name == "txBox" &&
      ["0", "1", "false", "true"].contains(a.value)
    }) else {
      @failure.reject("unsupported-layout", "Unknown shape nonvisual metadata")
    }
    self.shape_children(id, ["spLocks"])
  }
  guard self.drawing_child(shape, "spPr", uri=word_shape_uri)
    is Some(properties) &&
    self.nodes[properties].attributes.is_empty() else {
    @failure.reject("unsupported-layout", "Shape properties are required")
  }
  self.shape_children(properties, [
    "xfrm", "prstGeom", "custGeom", "solidFill", "noFill", "ln",
  ])
  let custom = self.drawing_child(properties, "custGeom")
  let ordinary = self.drawing_child(properties, "prstGeom")
  let selected = if ordinary is Some(_) { ordinary } else { custom }
  guard !(custom is Some(_) && ordinary is Some(_)) &&
    selected is Some(geometry) else {
    @failure.reject("unsupported-layout", "One shape geometry is required")
  }
  let points = if custom is Some(_) {
    self.shape_polyline(geometry)
  } else {
    []
  }
  let preset = if custom is Some(_) {
    "polyline"
  } else {
    self.nodes[geometry].attribute("prst").unwrap_or("")
  }
  guard ["rect", "ellipse", "line", "polyline"].contains(preset) &&
    (
      custom is Some(_) ||
      self.nodes[geometry].attributes.all(a => {
        a.uri.is_empty() && a.name == "prst"
      })
    ) &&
    (if preset == "line" {
      width > 0 || height > 0
    } else {
      width > 0 && height > 0
    }) else {
    @failure.reject(
      "unsupported-layout", "Shape preset or dimensions require support",
    )
  }
  if custom is None {
    self.shape_children(geometry, ["avLst"])
    if self.drawing_child(geometry, "avLst") is Some(id) {
      self.shape_children(id, [])
    }
  }
  if self.drawing_child(properties, "xfrm") is Some(id) {
    let node = self.nodes[id]
    guard node.attributes.all(a => {
      a.uri.is_empty() &&
      (
        (a.name == "rot" && a.value == "0") ||
        (
          ["flipH", "flipV"].contains(a.name) &&
          ["0", "false"].contains(a.value)
        )
      )
    }) else {
      @failure.reject(
        "unsupported-layout", "Rotated or flipped shape geometry requires support",
      )
    }
    self.shape_children(id, ["off", "ext"])
    for child in self.children[id] {
      let node = self.nodes[child]
      self.shape_children(child, [])
      let (x, y) = if node.name == "off" { ("x", "y") } else { ("cx", "cy") }
      guard node.attributes.all(a => a.uri.is_empty() && [x, y].contains(a.name)) &&
        drawing_number(node, x) == (if node.name == "off" { 0 } else { width }) &&
        drawing_number(node, y) == (if node.name == "off" { 0 } else { height }) else {
        @failure.reject(
          "unsupported-layout", "Shape transform differs from its frame",
        )
      }
    }
  }
  let (stroke, line_width) = if self.drawing_child(properties, "ln") is Some(id) {
    let node = self.nodes[id]
    guard node.attributes.all(a => {
      a.uri.is_empty() &&
      (
        a.name == "w" ||
        (preset == "polyline" && a.name == "cap" && a.value == "rnd")
      )
    }) else {
      @failure.reject("unsupported-layout", "Unknown shape line attributes")
    }
    self.shape_children(
      id,
      if preset == "polyline" {
        ["solidFill", "noFill", "prstDash", "round"]
      } else {
        ["solidFill", "noFill", "prstDash"]
      },
    )
    if self.drawing_child(id, "round") is Some(join) {
      self.shape_children(join, [])
      guard self.nodes[join].attributes.is_empty() else {
        @failure.reject("unsupported-layout", "Unknown ink stroke join")
      }
    }
    if self.drawing_child(id, "prstDash") is Some(dash) {
      self.shape_children(dash, [])
      guard self.nodes[dash].attribute("val") == Some("solid") &&
        self.nodes[dash].attributes.all(a => a.uri.is_empty() && a.name == "val") else {
        @failure.reject(
          "unsupported-layout", "Shape line dash requires support",
        )
      }
    }
    let stroke = self.shape_rgb(id, alpha=preset == "polyline")
    (
      stroke,
      if node.attribute("w") is Some(_) {
        drawing_number(node, "w")
      } else {
        0
      },
    )
  } else {
    ("", 0.0)
  }
  guard line_width <= 1584 && (stroke.is_empty() || line_width > 0) else {
    @failure.reject("unsupported-layout", "Shape line width requires support")
  }
  if preset == "polyline" {
    guard self.shape_rgb(properties).is_empty() &&
      !stroke.is_empty() &&
      self.drawing_child(properties, "ln") is Some(line) &&
      self.nodes[line].attribute("cap") == Some("rnd") &&
      self.drawing_child(line, "round") is Some(_) else {
      @failure.reject(
        "unsupported-layout", "Ink requires an unfilled round stroke",
      )
    }
  }
  {
    width,
    height,
    anchor,
    content: @layout.Shape({
      preset,
      fill: self.shape_rgb(properties),
      stroke,
      lineWidth: line_width,
      points,
      strokeAlpha: if preset == "polyline" {
        self
        .drawing_child(properties, "ln")
        .map(line => self.shape_stroke_alpha(line))
        .unwrap_or(1)
      } else {
        1
      },
    }),
  }
}
