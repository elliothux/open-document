///|
fn Session::sheet_chart_references(
  self : Session,
  old : String,
  name : String?,
  parts : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
  deleted~ : String? = None,
) -> Unit raise @failure.Failure {
  let seen : Set[String] = Set([])
  for sheet in self.sheets {
    if deleted == Some(sheet.id) {
      continue
    }
    if self.picture_drawing(sheet) is None {
      continue
    }
    guard self.font_context is Some((probe, profile)) else {
      @failure.reject(
        "missing-font", "Measure worksheet drawings before renaming",
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
          "limit-exceeded", "Worksheet chart references exceed budget",
        )
      }
      seen.add(part)
      let original = parts.get(part).unwrap_or_else(() => self.part_xml(part))
      let changes = sheet_reference_changes(original, old, name, charts=true)
      if !changes.is_empty() {
        let (document, edit) = original.edit_source(changes)
        parts[part] = document
        edits.push((part, edit))
        if name is None {
          object.freeze_chart_cache(part, parts, edits)
        }
      }
    }
  }
}
