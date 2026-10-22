///|
fn Session::axis_chart_references(
  self : Session,
  target : String,
  change : AxisChange,
  parts : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
) -> Unit raise @failure.Failure {
  let seen : Set[String] = Set([])
  for sheet in self.sheets {
    if self.picture_drawing(sheet) is None {
      continue
    }
    guard self.font_context is Some((probe, profile)) else {
      @failure.reject(
        "missing-font", "Measure worksheet charts before structural editing",
      )
    }
    let objects = self.sheet_objects(
      sheet,
      self.resolved_dimensions(sheet, probe, profile),
    )
    for object in objects {
      guard object.chart is Some((part, _)) && !seen.contains(part) else {
        continue
      }
      guard seen.length() < 256 else {
        @failure.reject(
          "limit-exceeded", "Structural chart references exceed budget",
        )
      }
      seen.add(part)
      let original = parts.get(part).unwrap_or_else(() => self.part_xml(part))
      let tree = Tree::new(original)
      let changes : Array[@xml.SourceChange] = []
      for node in original.nodes() {
        if node.uri != chart_uri ||
          node.name != "f" ||
          broken_chart_reference(node.text) {
          continue
        }
        let text = axis_formula(node.text, Some(sheet.name), target, change)
        changes.append(axis_text_change(tree, node, text))
      }
      if !changes.is_empty() {
        let (document, edit) = original.edit_source(changes)
        parts[part] = document
        edits.push((part, edit))
      }
    }
  }
}
