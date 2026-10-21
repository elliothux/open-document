///|
fn Picture::transform_change(
  self : Picture,
  rect : @layout.Border,
) -> @xml.SourceChange raise @failure.Failure {
  let props = self.tree.picture_node(self.source.id, "spPr")
  let xml = picture_transform(rect)
  if self.tree.picture_child(props.id, "xfrm", uri=picture_drawing_uri)
    is Some(node) {
    {
      node: props.id,
      offset: node.start - props.start,
      length: node.end - node.start,
      xml,
    }
  } else if props.empty {
    insertion(props, xml)
  } else {
    { node: props.id, offset: props.opening_end - props.start, length: 0, xml, }
  }
}

///|
fn Session::reflow_pictures(
  self : Session,
  sheets : Array[Sheet],
  parts : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
  context : (@layout.TextProbe, Map[String, String])?,
) -> Unit raise @failure.Failure {
  for sheet in sheets {
    guard self.sheets.iter().find_first(old => old.id == sheet.id) is Some(old) &&
      (
        !old.dimensions.rows.changed_ranges(sheet.dimensions.rows).is_empty() ||
        !old.dimensions.columns
        .changed_ranges(sheet.dimensions.columns)
        .is_empty() ||
        old.view.formulas != sheet.view.formulas
      ) else {
      continue
    }
    let tree = Tree::new(old.document)
    if tree.one(tree.root("worksheet").id, "drawing") is None {
      continue
    }
    guard context is Some((probe, profile)) else {
      @failure.reject(
        "missing-font", "Measure worksheet picture anchors with an explicit font profile before editing dimensions",
      )
    }
    let before = self.resolved_dimensions(old, probe, profile)
    let after = self.resolved_dimensions(sheet, probe, profile)
    let view = { ..self, parts, }
    let old_pictures = view.sheet_pictures(sheet, before) catch {
      @failure.Failure(code="unsupported-drawing", ..) => []
      error => raise error
    }
    let next_pictures = view.sheet_pictures(sheet, after) catch {
      @failure.Failure(code="unsupported-drawing", ..) => []
      error => raise error
    }
    if old_pictures.is_empty() {
      continue
    }
    let changes : Array[@xml.SourceChange] = []
    for picture in next_pictures {
      let previous = old_pictures
        .iter()
        .find_first(old => old.id == picture.id)
        .unwrap()
      if previous.rect.x != picture.rect.x ||
        previous.rect.y != picture.rect.y ||
        previous.rect.width != picture.rect.width ||
        previous.rect.height != picture.rect.height {
        changes.push(picture.transform_change(picture.rect))
      }
    }
    if !changes.is_empty() {
      let part = old_pictures[0].part
      let (document, edit) = old_pictures[0].tree.document.edit_source(changes)
      parts[part] = document
      edits.push((part, edit))
    }
  }
}
