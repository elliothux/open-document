///|
priv struct CustomGeometry {
  source : Ref
  fill : Bool
  stroke : Bool
}

///|
priv struct CustomFrame {
  path : Array[@layout.PathSegment]
  rect : (Double, Double, Double, Double)
  sites : Array[(Double, Double)]
}

///|
fn custom_value(
  value : String,
  guides : Map[String, Double],
) -> Double raise @failure.Failure {
  if guides.get(value) is Some(value) {
    return value
  }
  guard !value.is_empty() &&
    value.iter().all(c => c == '-' || c == '+' || (c >= '0' && c <= '9')) else {
    @failure.reject("unsupported-geometry", "Unknown custom geometry guide")
  }
  number(value, -2147483648, 2147483647)
}

///|
fn custom_guides(
  source : Ref,
  width : Double,
  height : Double,
) -> Map[String, Double] raise @failure.Failure {
  // ONLYOFFICE evaluates geometry in millimetres; literal path coordinates use EMU.
  let w = width * 12700 / 36000
  let h = height * 12700 / 36000
  let guides : Map[String, Double] = {
    "w": w,
    "h": h,
    "l": 0,
    "t": 0,
    "r": w,
    "b": h,
    "hc": w / 2,
    "vc": h / 2,
    "ss": w.min(h),
    "ls": w.max(h),
    "cd2": 10800000,
    "cd4": 5400000,
    "cd8": 2700000,
    "3cd4": 16200000,
    "3cd8": 8100000,
    "5cd8": 13500000,
    "7cd8": 18900000,
  }
  for divisor in [2, 3, 4, 5, 6, 8, 10, 12, 16, 32] {
    guides["wd\{divisor}"] = w / divisor.to_double()
    guides["hd\{divisor}"] = h / divisor.to_double()
    guides["ssd\{divisor}"] = w.min(h) / divisor.to_double()
  }
  let mut count = 0
  for name in ["avLst", "gdLst"] {
    if source.child(name) is Some(list) {
      for node in list.tree.children.get(list.node.id).unwrap_or([]) {
        count += 1
        guard count <= 128 else {
          @failure.reject(
            "limit-exceeded", "Custom geometry guide count exceeds budget",
          )
        }
        let name = node.attribute("name").unwrap_or("")
        let formula = node.attribute("fmla").unwrap_or("")
        guard !name.is_empty() &&
          name.length() <= 128 &&
          !guides.contains(name) &&
          formula.length() <= 256 else {
          @failure.reject(
            "unsupported-geometry", "Duplicate or invalid custom guide",
          )
        }
        let args = formula
          .split(" ")
          .filter(s => !s.is_empty())
          .map(s => s.to_owned())
          .to_array()
        let value = match args {
          ["val", x] => custom_value(x, guides)
          ["abs", x] => custom_value(x, guides).abs()
          ["min", x, y] => custom_value(x, guides).min(custom_value(y, guides))
          ["cos", x, y] =>
            custom_value(x, guides) *
            @math.cos(custom_value(y, guides) * @math.PI / 10800000)
          ["+-", x, y, z] =>
            custom_value(x, guides) +
            custom_value(y, guides) -
            custom_value(z, guides)
          ["*/", x, y, z] => {
            let denominator = custom_value(z, guides)
            guard denominator != 0 else {
              @failure.reject("malformed-pptx", "Custom guide divides by zero")
            }
            custom_value(x, guides) * custom_value(y, guides) / denominator
          }
          ["?:", x, y, z] => {
            let condition = custom_value(x, guides)
            let yes = custom_value(y, guides)
            let no = custom_value(z, guides)
            if condition > 0 {
              yes
            } else {
              no
            }
          }
          ["pin", x, y, z] => {
            let low = custom_value(x, guides)
            let value = custom_value(y, guides)
            let high = custom_value(z, guides)
            if value < low {
              low
            } else if value > high {
              high
            } else {
              value
            }
          }
          _ =>
            @failure.reject(
              "unsupported-geometry", "Unsupported custom guide formula",
            )
        }
        guard !value.is_nan() && value.abs() <= 1.0e15 else {
          @failure.reject("limit-exceeded", "Custom guide value exceeds budget")
        }
        guides[name] = value
      }
    }
  }
  guides
}

///|
fn read_custom_geometry(source : Ref) -> CustomGeometry raise @failure.Failure {
  let tree = source.tree
  let pending = [source.node]
  guard !source_xml(source).contains("<!--") &&
    !source_xml(source).contains("<?") else {
    @failure.reject(
      "unsupported-geometry", "Extended custom geometry is protected",
    )
  }
  while pending.pop() is Some(node) {
    let children = tree.children.get(node.id).unwrap_or([])
    pending.append(children)
    let keys = match node.name {
      "custGeom"
      | "avLst"
      | "gdLst"
      | "ahLst"
      | "cxnLst"
      | "pathLst"
      | "moveTo"
      | "lnTo"
      | "cubicBezTo"
      | "close" => []
      "gd" => ["name", "fmla"]
      "rect" => ["l", "t", "r", "b"]
      "path" => ["w", "h", "fill", "stroke", "extrusionOk"]
      "pt" | "pos" => ["x", "y"]
      "arcTo" => ["wR", "hR", "stAng", "swAng"]
      "cxn" => ["ang"]
      "ahXY" => ["gdRefX", "gdRefY", "minX", "maxX", "minY", "maxY"]
      _ =>
        @failure.reject(
          "unsupported-geometry", "Unsupported custom geometry command",
        )
    }
    guard node.uri == drawing_uri &&
      node.text.trim().is_empty() &&
      node.attributes.all(a => a.uri.is_empty() && keys.contains(a.name)) else {
      @failure.reject(
        "unsupported-geometry", "Unsupported custom geometry metadata",
      )
    }
    let valid = match node.name {
      "custGeom" => {
        let seen : Set[String] = Set([])
        children.all(n => {
          if !["avLst", "gdLst", "ahLst", "cxnLst", "rect", "pathLst"].contains(
              n.name,
            ) ||
            seen.contains(n.name) {
            false
          } else {
            seen.add(n.name)
            true
          }
        })
      }
      "avLst" | "gdLst" => children.all(n => n.name == "gd")
      "ahLst" => children.length() <= 128 && children.all(n => n.name == "ahXY")
      "cxnLst" => children.length() <= 256 && children.all(n => n.name == "cxn")
      "cxn" | "ahXY" => children is [{ name: "pos", .. }]
      "pathLst" => children is [{ name: "path", .. }]
      "path" =>
        children.length() >= 2 &&
        children.all(n => {
          ["moveTo", "lnTo", "cubicBezTo", "arcTo", "close"].contains(n.name)
        })
      "moveTo" | "lnTo" => children is [{ name: "pt", .. }]
      "cubicBezTo" =>
        children.length() == 3 && children.all(n => n.name == "pt")
      _ => children.is_empty()
    }
    guard valid else {
      @failure.reject(
        "unsupported-geometry", "Unsupported custom geometry structure",
      )
    }
  }
  guard source.child("pathLst").bind(l => l.child("path")) is Some(path) else {
    @failure.reject("unsupported-geometry", "Custom geometry requires one path")
  }
  let fill = path.node.attribute("fill").unwrap_or("norm")
  guard ["none", "norm"].contains(fill) else {
    @failure.reject("unsupported-geometry", "Unsupported custom path fill mode")
  }
  if path.node.attribute("extrusionOk") is Some(_) {
    ignore(flag(path.node, "extrusionOk"))
  }
  {
    source,
    fill: fill != "none",
    stroke: flag(path.node, "stroke", default=true),
  }
}

///|
fn custom_coordinate(
  text : String,
  guides : Map[String, Double],
  scale : Double?,
) -> Double raise @failure.Failure {
  let value = match (guides.get(text), scale) {
    (Some(value), scale) => value * scale.unwrap_or(1)
    (None, scale) => custom_value(text, guides) * scale.unwrap_or(1.0 / 36000)
  }
  let value = value * 36000 / 12700
  guard !value.is_nan() && value.abs() <= 1.0e9 else {
    @failure.reject("limit-exceeded", "Custom path coordinate exceeds budget")
  }
  value
}

///|
fn CustomGeometry::resolve(
  self : CustomGeometry,
  width : Double,
  height : Double,
) -> CustomFrame raise @failure.Failure {
  let source = self.source
  let guides = custom_guides(source, width, height)
  let path = source.child("pathLst").unwrap().child("path").unwrap()
  let scale = fn(key : String, dimension : Double) raise @failure.Failure {
    path.node
    .attribute(key)
    .map(text => dimension * 12700 / 36000 / number(text, 1, 2147483647))
  }
  let sx = scale("w", width)
  let sy = scale("h", height)
  let point = fn(node : @xml.Node) raise @failure.Failure {
    (
      custom_coordinate(node.attribute("x").unwrap_or(""), guides, sx),
      custom_coordinate(node.attribute("y").unwrap_or(""), guides, sy),
    )
  }
  let commands = source.tree.children.get(path.node.id).unwrap_or([])
  guard commands.length() <= 4097 else {
    @failure.reject(
      "limit-exceeded", "Custom path command count exceeds budget",
    )
  }
  let result : Array[@layout.PathSegment] = []
  let mut current = (0.0, 0.0)
  let mut first = current
  for index, command in commands {
    guard index != 0 || command.name == "moveTo" else {
      @failure.reject(
        "unsupported-geometry", "Custom path must start with a move",
      )
    }
    let children = source.tree.children.get(command.id).unwrap_or([])
    match command.name {
      "moveTo" | "lnTo" => {
        current = point(children[0])
        if command.name == "moveTo" {
          first = current
          result.push(Move(current.0, current.1))
        } else {
          result.push(Line(current.0, current.1))
        }
      }
      "cubicBezTo" => {
        let a = point(children[0])
        let b = point(children[1])
        current = point(children[2])
        result.push(Cubic(a.0, a.1, b.0, b.1, current.0, current.1))
      }
      "arcTo" => {
        let rx = custom_coordinate(
          command.attribute("wR").unwrap_or(""),
          guides,
          sx,
        )
        let ry = custom_coordinate(
          command.attribute("hR").unwrap_or(""),
          guides,
          sy,
        )
        let start = custom_value(
          command.attribute("stAng").unwrap_or(""),
          guides,
        )
        let sweep = custom_value(
          command.attribute("swAng").unwrap_or(""),
          guides,
        )
        guard start.abs() <= 2147483648 && sweep.abs() <= 21600000 else {
          @failure.reject("limit-exceeded", "Custom arc angle exceeds budget")
        }
        let arc = custom_arc(
          current,
          rx,
          ry,
          start,
          sweep,
          sx.unwrap_or(1),
          sy.unwrap_or(1),
        )
        result.append(arc)
        if arc.get(0) is Some(Move(x, y)) {
          first = (x, y)
        }
        if arc.last() is Some(Cubic(_, _, _, _, x, y)) {
          current = (x, y)
        }
      }
      "close" => {
        result.push(Close)
        current = first
      }
      _ =>
        @failure.reject(
          "unsupported-geometry", "Unsupported custom path command",
        )
    }
    guard result.length() <= 4097 else {
      @failure.reject("limit-exceeded", "Expanded custom path exceeds budget")
    }
  }
  let text_coordinate = fn(
    node : @xml.Node,
    key : String,
  ) raise @failure.Failure {
    let value = custom_value(node.attribute(key).unwrap_or(""), guides) *
      36000 /
      12700
    guard !value.is_nan() && value.abs() <= 1.0e9 else {
      @failure.reject(
        "limit-exceeded", "Custom geometry position exceeds budget",
      )
    }
    value
  }
  let rect = if source.child("rect") is Some(rect) {
    (
      text_coordinate(rect.node, "l"),
      text_coordinate(rect.node, "t"),
      text_coordinate(rect.node, "r"),
      text_coordinate(rect.node, "b"),
    )
  } else {
    (0.0, 0.0, width, height)
  }
  guard [rect.0, rect.1, rect.2, rect.3].all(v => {
    !v.is_nan() && v.abs() <= 1.0e9
  }) else {
    @failure.reject("limit-exceeded", "Custom text rectangle exceeds budget")
  }
  let sites : Array[(Double, Double)] = []
  if source.child("cxnLst") is Some(list) {
    for node in source.tree.children.get(list.node.id).unwrap_or([]) {
      ignore(custom_value(node.attribute("ang").unwrap_or(""), guides))
      let position = source.tree.children.get(node.id).unwrap()[0]
      sites.push(
        (text_coordinate(position, "x"), text_coordinate(position, "y")),
      )
    }
  }
  if source.child("ahLst") is Some(list) {
    for node in source.tree.children.get(list.node.id).unwrap_or([]) {
      for attr in node.attributes {
        ignore(custom_value(attr.value, guides))
      }
      let position = source.tree.children.get(node.id).unwrap()[0]
      ignore(text_coordinate(position, "x"))
      ignore(text_coordinate(position, "y"))
    }
  }
  { path: result, rect, sites, }
}

///|
fn Object::shape_path(
  self : Object,
  geometry : Geometry,
) -> Array[@layout.PathSegment] raise @failure.Failure {
  if self.custom is Some(custom) {
    custom.resolve(geometry.width, geometry.height).path
  } else {
    shape_path(self.preset, geometry.width, geometry.height, self.adjustments)
  }
}
