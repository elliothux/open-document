///|
fn Session::line_end_reason(self : Session, object : Object) -> String {
  let reason = self.pen_reason(object)
  if !reason.is_empty() {
    return reason
  }
  if object.preset != "line" {
    return "Line ends require a straight line"
  }
  try {
    for node in object.source.tree.document.nodes() {
      if node.start >= object.source.node.start &&
        node.end <= object.source.node.end &&
        node.name.has_suffix("Locks") &&
        flag(node, "noChangeArrowheads") {
        return "Line end editing is locked"
      }
    }
    if object.source
      .child("spPr", uri=presentation_uri)
      .bind(p => p.child("ln"))
      is Some(line) {
      for name in ["headEnd", "tailEnd"] {
        if line.child(name) is Some(end) {
          let source = source_xml(end)
          if source.contains("<!--") || source.contains("<?") {
            return "Retained line end markup is protected"
          }
        }
      }
    }
    ""
  } catch {
    @failure.Failure(message~, ..) => message
  }
}

///|
fn Session::line_end_changes(
  self : Session,
  head : Bool,
  value : LineEnd?,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  if value is Some(end) {
    end.validate() catch {
      _ => @failure.reject("invalid-operation", "Invalid line end")
    }
  }
  guard self.selection.mode == "object" && !self.selection.objects.is_empty() else {
    @failure.reject("invalid-operation", "Line ends require selected lines")
  }
  let changes : Array[@xml.SourceChange] = []
  let name = if head { "headEnd" } else { "tailEnd" }
  for id in self.selection.objects {
    let object = self.current().object(id)
    let reason = self.line_end_reason(object)
    guard reason.is_empty() else {
      @failure.reject("protected-content", reason)
    }
    let properties = object.source.child("spPr", uri=presentation_uri).unwrap()
    let line = properties.child("ln")
    let old = line.bind(line => line.child(name))
    let markup = value
      .map(end => {
        "<a:\{name} xmlns:a=\"\{drawing_uri}\" type=\"\{end.kind}\" w=\"\{end.width}\" len=\"\{end.length}\"/>"
      })
      .unwrap_or("")
    if line is Some(line) {
      if value is Some(end) && old is Some(_) && line_end([line], name) == end {
        continue
      }
      if value is None && old is None {
        continue
      }
      changes.push(
        paint_child_change(
          line,
          old.map(r => r.node),
          markup,
          if head {
            ["tailEnd", "extLst"]
          } else {
            ["extLst"]
          },
        ),
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
