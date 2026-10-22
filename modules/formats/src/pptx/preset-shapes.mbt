///|
fn arrow_shape(preset : String) -> Bool {
  ["rightArrow", "leftArrow", "upArrow", "downArrow"].contains(preset)
}

///|
fn line_shape(preset : String) -> Bool {
  ["line", "bentConnector3", "curvedConnector3"].contains(preset)
}

///|
fn supported_shape(preset : String) -> Bool {
  ["rect", "ellipse", "roundRect"].contains(preset) ||
  line_shape(preset) ||
  arrow_shape(preset) ||
  polygon_shape(preset)
}

///|
fn read_shape_adjustments(
  geometry : Ref?,
  preset : String,
) -> (Double, Double) raise @failure.Failure {
  let single = [
    "roundRect", "triangle", "parallelogram", "trapezoid", "hexagon", "octagon",
    "plus", "star5",
  ].contains(preset)
  let mut first = match preset {
    "roundRect" => 0.16667
    "parallelogram" | "trapezoid" | "hexagon" | "plus" => 0.25
    "octagon" => 0.29289
    "star5" => 0.19098
    _ => 0.5
  }
  let mut second = 0.5
  if !single &&
    !arrow_shape(preset) &&
    preset != "pentagon" &&
    !["bentConnector3", "curvedConnector3"].contains(preset) {
    return (first, second)
  }
  if geometry.bind(source => source.child("avLst")) is Some(list) {
    let seen : Map[String, Bool] = Map([])
    for node in list.tree.children.get(list.node.id).unwrap_or([]) {
      let name = node.attribute("name").unwrap_or("")
      let formula = node.attribute("fmla").unwrap_or("")
      let factor = match (preset, name) {
        ("pentagon" | "star5", "hf") => Some(1.05146)
        ("pentagon" | "star5", "vf") => Some(1.10557)
        ("hexagon", "vf") => Some(1.1547)
        _ => None
      }
      guard node.uri == drawing_uri &&
        node.name == "gd" &&
        (
          factor is Some(_) ||
          (if single {
            name == "adj"
          } else {
            (arrow_shape(preset) && ["adj1", "adj2"].contains(name)) ||
            (
              ["bentConnector3", "curvedConnector3"].contains(preset) &&
              name == "adj1"
            )
          })
        ) &&
        !seen.contains(name) &&
        formula.has_prefix("val ") else {
        @failure.reject(
          "unsupported-geometry", "Unsupported preset shape adjustment",
        )
      }
      seen[name] = true
      let value = number(formula[4:].trim().to_owned(), -2147483648, 2147483647) /
        100000
      if ["bentConnector3", "curvedConnector3"].contains(preset) {
        // shortcut: Out-of-frame bends need expanded object bounds before editing support.
        guard value >= 0 && value <= 1 else {
          @failure.reject(
            "unsupported-geometry", "Connector bend lies outside its frame",
          )
        }
      }
      if factor is Some(expected) {
        // shortcut: Nondefault normalization guides stay protected until custom preset guides are supported.
        guard value == expected else {
          @failure.reject(
            "unsupported-geometry", "Custom preset normalization requires support",
          )
        }
        continue
      }
      if name == "adj2" {
        second = value
      } else {
        first = value
      }
    }
  }
  (first, second)
}

///|
fn arrow_points(
  preset : String,
  width : Double,
  height : Double,
  adjustments : (Double, Double),
) -> Array[(Double, Double)] {
  let vertical = ["upArrow", "downArrow"].contains(preset)
  let w = if vertical { height } else { width }
  let h = if vertical { width } else { height }
  let head = (w.min(h) * adjustments.1).max(0).min(w)
  let half = h * adjustments.0.max(0).min(1) / 2
  let y1 = h / 2 - half
  let y2 = h / 2 + half
  let x1 = w - head
  [(0.0, y1), (x1, y1), (x1, 0.0), (w, h / 2), (x1, h), (x1, y2), (0.0, y2)].map(p => {
      match preset {
        "leftArrow" => (width - p.0, p.1)
        "upArrow" => (p.1, height - p.0)
        "downArrow" => (p.1, p.0)
        _ => p
      }
    },
  )
}

///|
fn Object::shape_body(self : Object, geometry : Geometry) -> Body {
  let w = geometry.width
  let h = geometry.height
  // ONLYOFFICE CreateGeometry text rectangles precede DrawingML body insets.
  let (left, top, right, bottom) = if self.preset == "roundRect" {
    let inset = w.min(h) * self.adjustments.0.max(0).min(0.5) * 0.29289
    (inset, inset, inset, inset)
  } else if polygon_shape(self.preset) {
    polygon_insets(self.preset, w, h, self.adjustments.0)
  } else if arrow_shape(self.preset) && w > 0 && h > 0 {
    let vertical = ["upArrow", "downArrow"].contains(self.preset)
    let length = if vertical { h } else { w }
    let across = if vertical { w } else { h }
    let side = across * (1 - self.adjustments.0.max(0).min(1)) / 2
    let head = (w.min(h) * self.adjustments.1).max(0).min(length)
    let tip = head - side * head / (across / 2)
    match self.preset {
      "leftArrow" => (tip, side, 0.0, side)
      "upArrow" => (side, tip, side, 0.0)
      "downArrow" => (side, 0.0, side, tip)
      _ => (0.0, side, tip, side)
    }
  } else {
    (0.0, 0.0, 0.0, 0.0)
  }
  {
    ..self.body,
    left: self.body.left + left,
    top: self.body.top + top,
    right: self.body.right + right,
    bottom: self.body.bottom + bottom,
  }
}

///|
fn Object::preset_hit(
  self : Object,
  geometry : Geometry,
  x : Double,
  y : Double,
  margin : Double,
) -> Bool {
  let width = geometry.width
  let height = geometry.height
  if width <= 0 || height <= 0 {
    return false
  }
  if self.preset == "roundRect" {
    let radius = width.min(height) * self.adjustments.0.max(0).min(0.5)
    let qx = (x - width / 2).abs() - (width / 2 - radius)
    let qy = (y - height / 2).abs() - (height / 2 - radius)
    let distance = (qx.max(0) * qx.max(0) + qy.max(0) * qy.max(0)).sqrt() +
      qx.max(qy).min(0) -
      radius
    return (self.has_fill() && distance <= 0) ||
      (!self.stroke.is_empty() && distance.abs() <= margin)
  }
  let points = if polygon_shape(self.preset) {
    polygon_points(self.preset, width, height, self.adjustments.0)
  } else {
    arrow_points(self.preset, width, height, self.adjustments)
  }
  let mut inside = false
  for i, (ax, ay) in points {
    let (bx, by) = points[(i + 1) % points.length()]
    if (ay > y) != (by > y) && x < (bx - ax) * (y - ay) / (by - ay) + ax {
      inside = !inside
    }
    let dx = bx - ax
    let dy = by - ay
    let length = dx * dx + dy * dy
    let t = (if length > 0 {
        ((x - ax) * dx + (y - ay) * dy) / length
      } else {
        0.0
      })
      .max(0)
      .min(1)
    let gap_x = x - ax - t * dx
    let gap_y = y - ay - t * dy
    if !self.stroke.is_empty() &&
      gap_x * gap_x + gap_y * gap_y <= margin * margin {
      return true
    }
  }
  self.has_fill() && inside
}
