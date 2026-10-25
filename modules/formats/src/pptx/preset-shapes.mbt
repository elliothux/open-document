///|
fn arrow_shape(preset : String) -> Bool {
  ["rightArrow", "leftArrow", "upArrow", "downArrow", "notchedRightArrow"].contains(
    preset,
  ) ||
  double_arrow_shape(preset) ||
  elbow_arrow_shape(preset) ||
  branched_arrow_shape(preset)
}

///|
fn branched_arrow_shape(preset : String) -> Bool {
  ["quadArrow", "leftRightUpArrow"].contains(preset)
}

///|
fn double_arrow_shape(preset : String) -> Bool {
  ["leftRightArrow", "upDownArrow"].contains(preset)
}

///|
fn vertical_arrow_shape(preset : String) -> Bool {
  ["upArrow", "downArrow", "upDownArrow"].contains(preset)
}

///|
fn line_shape(preset : String) -> Bool {
  [
    "line", "bentConnector2", "bentConnector3", "bentConnector4", "bentConnector5",
  ].contains(preset) ||
  curved_connector(preset)
}

///|
fn supported_shape(preset : String) -> Bool {
  ["rect", "ellipse"].contains(preset) ||
  rounded_shape(preset) ||
  line_shape(preset) ||
  arrow_shape(preset) ||
  polygon_shape(preset)
}

///|
fn paired_corner_shape(preset : String) -> Bool {
  [
    "snip2SameRect", "snip2DiagRect", "round2SameRect", "round2DiagRect", "snipRoundRect",
  ].contains(preset)
}

///|
fn read_shape_adjustments(
  geometry : Ref?,
  preset : String,
) -> (Double, Double, Double) raise @failure.Failure {
  let single = [
    "roundRect", "triangle", "parallelogram", "trapezoid", "hexagon", "octagon",
    "plus", "star4", "star5", "star6", "star7", "star8", "star10", "star12", "star16",
    "star24", "star32", "chevron", "homePlate", "snip1Rect", "round1Rect",
  ].contains(preset)
  let mut first = match preset {
    "roundRect"
    | "snip1Rect"
    | "snip2SameRect"
    | "round1Rect"
    | "round2SameRect"
    | "round2DiagRect"
    | "snipRoundRect" => 0.16667
    "snip2DiagRect" => 0.0
    "parallelogram" | "trapezoid" | "hexagon" | "plus" => 0.25
    "octagon" => 0.29289
    "star5" => 0.19098
    "star4" => 0.125
    "star6" => 0.28868
    "star7" => 0.34601
    "star8" | "star12" | "star16" | "star24" | "star32" => 0.375
    "star10" => 0.42533
    "quadArrow" => 0.225
    "leftRightUpArrow" | "leftUpArrow" | "bentUpArrow" => 0.25
    _ => 0.5
  }
  let mut second = match preset {
    "snip2SameRect" | "round2SameRect" | "round2DiagRect" => 0.0
    "snip2DiagRect" | "snipRoundRect" => 0.16667
    _ =>
      if branched_arrow_shape(preset) || elbow_arrow_shape(preset) {
        first
      } else {
        0.5
      }
  }
  let mut third = if ["bentConnector5", "curvedConnector5"].contains(preset) {
    0.5
  } else if branched_arrow_shape(preset) || elbow_arrow_shape(preset) {
    first
  } else {
    0.0
  }
  if ["bentConnector2", "curvedConnector2"].contains(preset) &&
    geometry.bind(source => source.child("avLst")) is Some(list) {
    guard list.node.attributes.is_empty() &&
      list.node.text.trim().is_empty() &&
      list.tree.children.get(list.node.id).unwrap_or([]).is_empty() else {
      @failure.reject(
        "unsupported-geometry", "This connector preset does not have adjustment guides",
      )
    }
  }
  if !single &&
    !arrow_shape(preset) &&
    !paired_corner_shape(preset) &&
    !["pentagon", "heptagon", "decagon", "dodecagon"].contains(preset) &&
    ![
      "bentConnector3", "bentConnector4", "bentConnector5", "curvedConnector3", "curvedConnector4",
      "curvedConnector5",
    ].contains(preset) {
    return (first, second, third)
  }
  if geometry.bind(source => source.child("avLst")) is Some(list) {
    let seen : Map[String, Bool] = Map([])
    for node in list.tree.children.get(list.node.id).unwrap_or([]) {
      let name = node.attribute("name").unwrap_or("")
      let formula = node.attribute("fmla").unwrap_or("")
      let factor = match (preset, name) {
        ("pentagon" | "star5" | "star10", "hf") => Some(1.05146)
        ("star6", "hf") => Some(1.1547)
        ("star7" | "heptagon", "hf") => Some(1.02572)
        ("star7" | "heptagon", "vf") => Some(1.05210)
        ("decagon", "vf") => Some(1.05146)
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
            (
              (arrow_shape(preset) || paired_corner_shape(preset)) &&
              ["adj1", "adj2"].contains(name)
            ) ||
            (
              (branched_arrow_shape(preset) || elbow_arrow_shape(preset)) &&
              name == "adj3"
            ) ||
            (
              [
                "bentConnector3", "bentConnector4", "bentConnector5", "curvedConnector3",
                "curvedConnector4", "curvedConnector5",
              ].contains(preset) &&
              name == "adj1"
            ) ||
            (
              [
                "bentConnector4", "bentConnector5", "curvedConnector4", "curvedConnector5",
              ].contains(preset) &&
              name == "adj2"
            ) ||
            (
              ["bentConnector5", "curvedConnector5"].contains(preset) &&
              name == "adj3"
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
      if [
          "bentConnector3", "bentConnector4", "bentConnector5", "curvedConnector3",
          "curvedConnector4", "curvedConnector5",
        ].contains(preset) {
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
      if name == "adj3" {
        third = value
      } else if name == "adj2" {
        second = value
      } else {
        first = value
      }
    }
  }
  (first, second, third)
}

///|
fn branched_arrow_adjustments(
  values : (Double, Double, Double),
) -> (Double, Double, Double) {
  let width = values.1.clamp(min=0, max=0.5)
  (
    values.0.clamp(min=0, max=2 * width),
    width,
    values.2.clamp(min=0, max=((0.5 - width) * 100000).round() / 100000),
  )
}

///|
fn arrow_points(
  preset : String,
  width : Double,
  height : Double,
  adjustments : (Double, Double, Double),
) -> Array[(Double, Double)] {
  if elbow_arrow_shape(preset) {
    return elbow_arrow_points(preset, width, height, adjustments)
  }
  if branched_arrow_shape(preset) {
    let (shaft, head_width, head_length) = branched_arrow_adjustments(
      adjustments,
    )
    let side = width.min(height)
    let x1 = side * head_length
    let dx2 = side * head_width
    let dx3 = side * shaft / 2
    let x2 = width / 2 - dx2
    let x3 = width / 2 - dx3
    let x4 = width / 2 + dx3
    let x5 = width / 2 + dx2
    let x6 = width - x1
    let center = if preset == "leftRightUpArrow" {
      height - dx2
    } else {
      height / 2
    }
    let y2 = center - dx2
    let y3 = center - dx3
    let y4 = center + dx3
    let y5 = center + dx2
    let y6 = height - x1
    let points = [
      (0.0, center),
      (x1, y2),
      (x1, y3),
      (x3, y3),
      (x3, x1),
      (x2, x1),
      (width / 2, 0.0),
      (x5, x1),
      (x4, x1),
      (x4, y3),
      (x6, y3),
      (x6, y2),
      (width, center),
    ]
    if preset == "leftRightUpArrow" {
      points.append([(x6, height), (x6, y4), (x1, y4), (x1, height)])
    } else {
      points.append([
        (x6, y5),
        (x6, y4),
        (x4, y4),
        (x4, y6),
        (x5, y6),
        (width / 2, height),
        (x2, y6),
        (x3, y6),
        (x3, y4),
        (x1, y4),
        (x1, y5),
      ])
    }
    return points
  }
  let vertical = vertical_arrow_shape(preset)
  let w = if vertical { height } else { width }
  let h = if vertical { width } else { height }
  let head = (w.min(h) * adjustments.1)
    .max(0)
    .min(if double_arrow_shape(preset) { w / 2 } else { w })
  let half = h * adjustments.0.max(0).min(1) / 2
  let y1 = h / 2 - half
  let y2 = h / 2 + half
  let x1 = w - head
  if preset == "leftRightArrow" {
    return [
      (0.0, h / 2),
      (head, 0.0),
      (head, y1),
      (x1, y1),
      (x1, 0.0),
      (w, h / 2),
      (x1, h),
      (x1, y2),
      (head, y2),
      (head, h),
    ]
  }
  if preset == "upDownArrow" {
    return [
      (0.0, head),
      (h / 2, 0.0),
      (h, head),
      (y2, head),
      (y2, x1),
      (h, x1),
      (h / 2, w),
      (0.0, x1),
      (y1, x1),
      (y1, head),
    ]
  }
  let points = [
    (0.0, y1),
    (x1, y1),
    (x1, 0.0),
    (w, h / 2),
    (x1, h),
    (x1, y2),
    (0.0, y2),
  ]
  if preset == "notchedRightArrow" {
    points.push((head * adjustments.0.clamp(min=0, max=1), h / 2))
  }
  points.map(p => {
    match preset {
      "leftArrow" => (width - p.0, p.1)
      "upArrow" => (p.1, height - p.0)
      "downArrow" => (p.1, p.0)
      _ => p
    }
  })
}

///|
fn Object::shape_body(self : Object, geometry : Geometry) -> Body {
  let w = geometry.width
  let h = geometry.height
  // ONLYOFFICE CreateGeometry text rectangles precede DrawingML body insets.
  let (left, top, right, bottom) = if rounded_shape(self.preset) {
    rounded_insets(self.preset, w, h, self.adjustments)
  } else if elbow_arrow_shape(self.preset) {
    elbow_arrow_insets(self.preset, w, h, self.adjustments)
  } else if branched_arrow_shape(self.preset) {
    let (shaft, head_width, head_length) = branched_arrow_adjustments(
      self.adjustments,
    )
    let side = w.min(h)
    let inset = if head_width > 0 {
      side * shaft * head_length / (2 * head_width)
    } else {
      0.0
    }
    let center = if self.preset == "leftRightUpArrow" {
      h - side * head_width
    } else {
      h / 2
    }
    (inset, center - side * shaft / 2, inset, h - center - side * shaft / 2)
  } else if polygon_shape(self.preset) {
    polygon_insets(
      self.preset,
      w,
      h,
      self.adjustments.0,
      second=self.adjustments.1,
    )
  } else if arrow_shape(self.preset) && w > 0 && h > 0 {
    let vertical = vertical_arrow_shape(self.preset)
    let length = if vertical { h } else { w }
    let across = if vertical { w } else { h }
    let side = across * (1 - self.adjustments.0.max(0).min(1)) / 2
    let head = (w.min(h) * self.adjustments.1)
      .max(0)
      .min(if double_arrow_shape(self.preset) { length / 2 } else { length })
    let tip = head - side * head / (across / 2)
    match self.preset {
      "leftRightArrow" | "notchedRightArrow" => (tip, side, tip, side)
      "upDownArrow" => (side, tip, side, tip)
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
  if rounded_shape(self.preset) {
    return self.rounded_hit(width, height, x, y, margin)
  }
  let points = if polygon_shape(self.preset) {
    polygon_points(
      self.preset,
      width,
      height,
      self.adjustments.0,
      second=self.adjustments.1,
    )
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
