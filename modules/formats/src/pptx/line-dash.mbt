///|
fn dash_pattern(value : String) -> Array[Double] raise @failure.Failure {
  // DrawingML presets use stroke-width multiples (ONLYOFFICE DashPatternPresets).
  match value {
    "solid" => []
    "dash" => [4, 3]
    "dashDot" => [4, 3, 1, 3]
    "dot" => [1, 3]
    "lgDash" => [8, 3]
    "lgDashDot" => [8, 3, 1, 3]
    "lgDashDotDot" => [8, 3, 1, 3, 1, 3]
    "sysDash" => [3, 1]
    "sysDashDot" => [3, 1, 1, 1]
    "sysDashDotDot" => [3, 1, 1, 1, 1, 1]
    "sysDot" => [1, 1]
    _ => @failure.reject("unsupported-style", "Unknown DrawingML border dash")
  }
}

///|
fn dash_override(line : Ref) -> Ref? raise @failure.Failure {
  let children = line.tree.children.get(line.node.id).unwrap_or([])
  let presets = children.filter(n => {
    n.uri == drawing_uri && n.name == "prstDash"
  })
  guard presets.length() <= 1 &&
    !children.any(n => n.uri == drawing_uri && n.name == "custDash") else {
    @failure.reject(
      "unsupported-style", "Custom or duplicate border dashes are unsupported",
    )
  }
  guard presets.get(0) is Some(node) else { return None }
  guard node.text.trim().is_empty() &&
    node.attributes.all(a => a.uri.is_empty() && a.name == "val") &&
    line.tree.children.get(node.id).unwrap_or([]).is_empty() else {
    @failure.reject("unsupported-style", "Unknown border dash properties")
  }
  ignore(dash_pattern(node.attribute("val").unwrap_or("solid")))
  Some({ tree: line.tree, node, })
}

///|
fn line_dash(sources : Array[Ref]) -> String raise @failure.Failure {
  for line in sources {
    if dash_override(line) is Some(preset) {
      return preset.node.attribute("val").unwrap_or("solid")
    }
  }
  "solid"
}

///|
fn Session::dash_reason(self : Session, object : Object) -> String {
  let reason = self.paint_reason(object)
  if !reason.is_empty() {
    return reason
  }
  try {
    let properties = object.source.child("spPr", uri=presentation_uri).unwrap()
    guard properties.tree.children
      .get(properties.node.id)
      .unwrap_or([])
      .filter(n => n.uri == drawing_uri && n.name == "ln")
      .length() <=
      1 else {
      return "Duplicate border properties are protected"
    }
    if object.source
      .child("spPr", uri=presentation_uri)
      .bind(p => p.child("ln"))
      is Some(line) &&
      dash_override(line) is Some(dash) {
      let source = source_xml(dash)
      if source.contains("<!--") || source.contains("<?") {
        return "Retained border dash markup is protected"
      }
    }
    ""
  } catch {
    @failure.Failure(message~, ..) => message
  }
}

///|
fn Session::dash_objects(
  self : Session,
  value : String?,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  if value is Some(value) {
    ignore(dash_pattern(value)) catch {
      @failure.Failure(..) =>
        @failure.reject("invalid-operation", "Unknown border dash")
    }
  }
  guard self.selection.mode == "object" && !self.selection.objects.is_empty() else {
    @failure.reject(
      "invalid-operation", "Border dash editing requires selected objects",
    )
  }
  let changes = []
  for id in self.selection.objects {
    let object = self.current().object(id)
    let reason = self.dash_reason(object)
    guard reason.is_empty() else {
      @failure.reject("protected-content", reason)
    }
    let properties = object.source.child("spPr", uri=presentation_uri).unwrap()
    let markup = value
      .map(v => "<a:prstDash xmlns:a=\"\{drawing_uri}\" val=\"\{v}\"/>")
      .unwrap_or("")
    if properties.child("ln") is Some(line) {
      let preset = dash_override(line)
      if value == preset.map(p => p.node.attribute("val").unwrap_or("solid")) {
        continue
      }
      changes.push(
        paint_child_change(line, preset.map(p => p.node), markup, [
          "round", "bevel", "miter", "headEnd", "tailEnd", "extLst",
        ]),
      )
    } else if value is Some(_) {
      changes.push(
        paint_child_change(
          properties,
          None,
          "<a:ln xmlns:a=\"\{drawing_uri}\">\{markup}</a:ln>",
          ["effectLst", "effectDag", "scene3d", "sp3d", "extLst"],
        ),
      )
    }
  }
  changes
}
