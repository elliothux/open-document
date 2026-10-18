///|
fn shape_gradient(
  fill : Ref,
  theme : Theme,
  placeholder : Ref?,
) -> (Array[@layout.GradientStop], Double, Bool) raise @failure.Failure {
  let (points, angle, scaled) = linear_background_source(fill)
  guard [None, Some("1"), Some("true")].contains(
    fill.node.attribute("rotWithShape"),
  ) else {
    @failure.reject(
      "unsupported-style", "Fixed-angle shape gradients are unsupported",
    )
  }
  (
    points.map(point => {
      let (color, opacity) = color_rgba(theme, point.0, placeholder~)
      { position: point.1, color, opacity, }
    }),
    angle,
    scaled,
  )
}

///|
fn Session::gradient_objects(
  self : Session,
  value : BackgroundFill,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let value = value.normalized()
  guard value is Linear(stops, angle, scaled) else {
    @failure.reject(
      "invalid-operation", "Shape gradient requires linear colors",
    )
  }
  guard self.selection.mode == "object" && !self.selection.objects.is_empty() else {
    @failure.reject(
      "invalid-operation", "Appearance editing requires selected objects",
    )
  }
  let changes = []
  for id in self.selection.objects {
    let object = self.current().object(id)
    let reason = self.paint_reason(object)
    guard reason.is_empty() else {
      @failure.reject("protected-content", reason)
    }
    let properties = object.source.child("spPr", uri=presentation_uri).unwrap()
    let child = paint_fill(properties)
    let use_background = flag(object.source.node, "useBgFill")
    if child is Some(node) &&
      node.name == "gradFill" &&
      object.gradient == Some((stops, angle, scaled)) &&
      !use_background {
      continue
    }
    changes.push(
      paint_child_change(properties, child, value.markup(), [
        "ln", "effectLst", "effectDag", "scene3d", "sp3d", "extLst",
      ]),
    )
    if use_background {
      changes.push(attribute_change(object.source, "useBgFill", "0"))
    }
  }
  changes
}
