///|
fn Object::adjustment_values(self : Object) -> Array[(String, Double, Double)] {
  if self.kind != "shape" {
    return []
  }
  if branched_arrow_shape(self.preset) {
    let (shaft, width, length) = branched_arrow_adjustments(self.adjustments)
    return [
      ("adj1", shaft, 2 * width),
      ("adj2", width, 0.5),
      ("adj3", length, ((0.5 - width) * 100000).round() / 100000),
    ]
  }
  if self.preset == "roundRect" {
    return [("adj", self.adjustments.0.max(0).min(0.5), 0.5)]
  }
  if ["bentConnector3", "curvedConnector3"].contains(self.preset) {
    return [("adj1", self.adjustments.0, 1.0)]
  }
  if [
      "triangle", "parallelogram", "trapezoid", "hexagon", "octagon", "plus", "star5",
      "star4", "star6", "star8", "chevron", "homePlate",
    ].contains(self.preset) &&
    self.geometry is Some(geometry) {
    let maximum = polygon_adjustment_max(
      self.preset,
      geometry.width,
      geometry.height,
    ).min(21474.83647)
    return [("adj", self.adjustments.0.max(0).min(maximum), maximum)]
  }
  guard arrow_shape(self.preset) && self.geometry is Some(geometry) else {
    return []
  }
  let shortest = geometry.width.min(geometry.height)
  guard shortest > 0 else { return [] }
  let length = if vertical_arrow_shape(self.preset) {
    geometry.height
  } else {
    geometry.width
  }
  // ONLYOFFICE CreateGeometry bounds the arrow head by length / shortest side.
  let maximum = (length /
  shortest /
  (if double_arrow_shape(self.preset) { 2.0 } else { 1.0 })).min(21474.83647)
  [
    ("adj1", self.adjustments.0.max(0).min(1), 1.0),
    ("adj2", self.adjustments.1.max(0).min(maximum), maximum),
  ]
}

///|
fn Session::adjustment_reason(self : Session, object : Object) -> String {
  let reason = self.appearance_reason(object)
  if !reason.is_empty() {
    return reason
  }
  if object.adjustment_values().is_empty() {
    return "This shape has no supported adjustments"
  }
  try {
    guard object.source.child("spPr", uri=presentation_uri) is Some(properties) &&
      properties.child("prstGeom") is Some(geometry) &&
      geometry.node.attribute("prst") == Some(object.preset) else {
      return "Adjustments require local preset geometry"
    }
    let nodes = object.source.tree.document.nodes()
    for node in nodes {
      if node.start >= object.source.node.start &&
        node.end <= object.source.node.end &&
        node.name.has_suffix("Locks") &&
        flag(node, "noAdjustHandles") {
        return "Shape adjustments are locked"
      }
    }
    if geometry.child("avLst") is Some(list) {
      let source = source_xml(list)
      guard list.node.attributes.is_empty() &&
        list.node.text.trim().is_empty() &&
        !source.contains("<!--") &&
        !source.contains("<?") else {
        return "Unknown shape adjustment markup is protected"
      }
      for node in list.tree.children.get(list.node.id).unwrap_or([]) {
        guard node.uri == drawing_uri &&
          node.name == "gd" &&
          node.text.trim().is_empty() &&
          node.attributes.all(a => {
            a.uri.is_empty() && ["name", "fmla"].contains(a.name)
          }) &&
          list.tree.children.get(node.id).unwrap_or([]).is_empty() else {
          return "Unknown shape adjustment guide is protected"
        }
      }
    }
    if object.body.fit != "none" && !object.paragraphs.is_empty() {
      return self.text_frame_reason(object)
    }
    ""
  } catch {
    @failure.Failure(message~, ..) => message
  }
}

///|
fn Session::shape_adjustments(self : Session, object : Object) -> Json {
  let values = object
    .adjustment_values()
    .map(item => {
      let value : Json = { "name": item.0, "value": item.1, "maximum": item.2 }
      value
    })
  {
    "preset": object.preset,
    "reason": self.adjustment_reason(object),
    "values": values,
  }
}

///|
fn Session::adjust_shape(
  self : Session,
  name : String,
  value : Double?,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  guard ["adj", "adj1", "adj2", "adj3"].contains(name) else {
    @failure.reject("invalid-operation", "Unknown shape adjustment")
  }
  if value is Some(value) {
    guard !value.is_nan() &&
      !value.is_inf() &&
      value >= 0 &&
      value <= 21474.83647 else {
      @failure.reject("invalid-operation", "Invalid shape adjustment value")
    }
  }
  guard self.selection.mode == "object" && !self.selection.objects.is_empty() else {
    @failure.reject(
      "invalid-operation", "Shape adjustments require selected objects",
    )
  }
  let changes = []
  for id in self.selection.objects {
    let object = self.current().object(id)
    let reason = self.adjustment_reason(object)
    guard reason.is_empty() else {
      @failure.reject("protected-content", reason)
    }
    guard object.adjustment_values().iter().find_first(item => item.0 == name)
      is Some(item) else {
      @failure.reject(
        "invalid-operation", "Adjustment does not belong to this shape",
      )
    }
    if value is Some(value) {
      guard value <= item.2 else {
        @failure.reject(
          "invalid-operation", "Shape adjustment exceeds its geometric limit",
        )
      }
    }
    let geometry = object.source
      .child("spPr", uri=presentation_uri)
      .unwrap()
      .child("prstGeom")
      .unwrap()
    let list = geometry.child("avLst")
    let guide = list.bind(list => {
      list.tree.children
      .get(list.node.id)
      .unwrap_or([])
      .iter()
      .find_first(n => n.attribute("name") == Some(name))
    })
    if value is Some(value) {
      let formula = "val \{(value * 100000).round().to_int64()}"
      if guide is None && (item.1 * 100000).round() == (value * 100000).round() {
        continue
      }
      if guide is Some(guide) {
        if guide.attribute("fmla") != Some(formula) {
          changes.push(
            attribute_change(
              { tree: geometry.tree, node: guide, },
              "fmla",
              formula,
            ),
          )
        }
      } else {
        let markup = "<a:gd xmlns:a=\"\{drawing_uri}\" name=\"\{name}\" fmla=\"\{formula}\"/>"
        changes.push(
          if list is Some(list) {
            insertion(list.node, markup)
          } else {
            insertion(
              geometry.node,
              "<a:avLst xmlns:a=\"\{drawing_uri}\">\{markup}</a:avLst>",
            )
          },
        )
      }
    } else if guide is Some(guide) {
      let list = list.unwrap()
      changes.push({
        node: list.node.id,
        offset: guide.start - list.node.start,
        length: guide.end - guide.start,
        xml: "",
      })
    }
  }
  changes
}
