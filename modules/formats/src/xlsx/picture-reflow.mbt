///|
fn SheetObject::transform_change(
  self : SheetObject,
  rect : @layout.Border,
) -> @xml.SourceChange raise @failure.Failure {
  let props = if self.chart is Some(_) {
    self.source
  } else {
    self.tree.picture_node(self.source.id, "spPr")
  }
  let uri = if self.chart is Some(_) {
    picture_uri
  } else {
    picture_drawing_uri
  }
  let xml = if self.chart is Some(_) {
    chart_transform(rect)
  } else {
    picture_transform(rect)
  }
  if self.tree.picture_child(props.id, "xfrm", uri~) is Some(node) {
    if self.chart is Some(_) {
      let source = self.tree.picture_markup(node.id)
      guard !source.contains("<!--") && !source.contains("<?") else {
        @failure.reject(
          "protected-content", "Chart transform annotations require source-preserving editing",
        )
      }
    }
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
fn SheetObject::transform_matches(self : SheetObject) -> Bool {
  try {
    let props = if self.chart is Some(_) {
      self.source
    } else {
      self.tree.picture_node(self.source.id, "spPr")
    }
    let transform = self.tree.picture_node(
      props.id,
      "xfrm",
      uri=if self.chart is Some(_) { picture_uri } else { picture_drawing_uri },
    )
    let position = self.tree.picture_node(
      transform.id,
      "off",
      uri=picture_drawing_uri,
    )
    let extent = self.tree.picture_node(
      transform.id,
      "ext",
      uri=picture_drawing_uri,
    )
    [
      (position, "x", self.rect.x),
      (position, "y", self.rect.y),
      (extent, "cx", self.rect.width),
      (extent, "cy", self.rect.height),
    ].all(entry => {
      let (node, name, value) = entry
      picture_integer(node.attribute(name).unwrap_or("")) ==
      (value * 12700).round()
    })
  } catch {
    @failure.Failure(..) => false
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
    let tree = Tree::new(sheet.document)
    if tree.one(tree.root("worksheet").id, "drawing") is None {
      continue
    }
    guard context is Some((probe, profile)) else {
      @failure.reject(
        "missing-font", "Measure worksheet picture anchors with an explicit font profile before editing dimensions",
      )
    }
    let after = self.resolved_dimensions(sheet, probe, profile)
    let view = { ..self, parts, }
    let next_pictures = view.sheet_objects(sheet, after) catch {
      @failure.Failure(code="unsupported-drawing", ..) => []
      error => raise error
    }
    let changes : Array[@xml.SourceChange] = []
    for picture in next_pictures {
      if picture.anchor != "fixed" && !picture.transform_matches() {
        changes.push(picture.transform_change(picture.rect))
      }
    }
    if !changes.is_empty() {
      let part = next_pictures[0].part
      let (document, edit) = next_pictures[0].tree.document.edit_source(changes)
      parts[part] = document
      edits.push((part, edit))
    }
  }
}
