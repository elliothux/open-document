///|
fn Session::move_drawing(
  self : Session,
  source_sheet : String,
  id : String,
  target_sheet : String,
) -> Json raise @failure.Failure {
  guard id.length() <= 10 else {
    @failure.reject("invalid-operation", "Invalid worksheet drawing identity")
  }
  let source = self.sheets[self.sheet_index(source_sheet)]
  let target_index = self.sheet_index(target_sheet)
  let target = self.sheets[target_index]
  for sheet in [source, target] {
    let reason = self.dimension_reason(sheet)
    guard reason.is_empty() else {
      @failure.reject("protected-content", reason)
    }
  }
  guard self.font_context is Some((probe, profile)) else {
    @failure.reject("missing-font", "Measure worksheet drawings before moving")
  }
  let before = self.resolved_dimensions(source, probe, profile)
  let dimensions = self.resolved_dimensions(target, probe, profile)
  let object = self
    .sheet_objects(source, before)
    .iter()
    .find_first(object => object.id == id)
    .unwrap_or_else(() => {
      @failure.reject("invalid-operation", "Worksheet drawing no longer exists")
    })
  let identity = object.transfer_identity(false)
  let objects = self.sheet_objects(target, dimensions)
  guard source_sheet == target_sheet || objects.length() < 256 else {
    @failure.reject("limit-exceeded", "Worksheet drawings exceed 256 entries")
  }
  let range = if self.selection.0 == target_sheet {
    self.selection.1
  } else {
    Range::parse("A1")
  }
  let rect = {
    ..object.rect,
    x: dimensions.columns.position(range.left),
    y: dimensions.rows.position(range.top),
  }
  guard rect.x + rect.width <= dimensions.columns.position(16385) &&
    rect.y + rect.height <= dimensions.rows.position(1048577) else {
    @failure.reject(
      "invalid-operation", "Moved drawing would exceed the worksheet",
    )
  }
  if source_sheet == target_sheet &&
    rect.x == object.rect.x &&
    rect.y == object.rect.y {
    return self.query()
  }
  let next_id = if source_sheet == target_sheet ||
    !objects.any(object => object.id == id) {
    id
  } else {
    for index in 1..<=16384 {
      if !objects.any(object => object.id == index.to_string()) {
        break index.to_string()
      }
    } nobreak {
      @failure.reject(
        "limit-exceeded", "Worksheet drawing identities exhausted",
      )
    }
  }
  let changes = object.transfer_changes(identity, next_id, rect, dimensions)
  let parts = self.parts.copy()
  let created : Map[String, @xml.Document] = Map([])
  let edits : Array[(String, @xml.Edit)] = []
  let (drawing, sheet_document) = match self.picture_drawing(target) {
    Some((part, _)) => (part, target.document)
    None => {
      let (part, relation) = self.create_sheet_resource(
        target_sheet,
        "drawing",
        "<xdr:wsDr xmlns:xdr=\"\{picture_uri}\"/>",
        parts,
        created,
        edits,
      )
      let (document, edit) = insert_sheet_drawing(
        target.document,
        relation,
        name="drawing",
      )
      edits.push((target_sheet, edit))
      (part, document)
    }
  }
  if object.part != drawing {
    let resource = if object.media is Some(part) {
      Some((part, "image", @image.type_info(self.picture_bytes(part)).1))
    } else {
      object.chart.map(chart => {
        (
          chart.0,
          "chart",
          "application/vnd.openxmlformats-officedocument.drawingml.chart+xml",
        )
      })
    }
    if resource is Some((part, kind, mime)) {
      let node = object.tree.document
        .nodes()
        .iter()
        .find_first(node => {
          node.start >= object.source.start &&
          node.end <= object.source.end &&
          (
            (
              kind == "image" &&
              node.uri == picture_drawing_uri &&
              node.name == "blip"
            ) ||
            (kind == "chart" && node.uri == chart_uri && node.name == "chart")
          )
        })
        .unwrap()
      let attr = node.attributes
        .iter()
        .find_first(a => {
          a.uri == relationship_uri[:relationship_uri.length() - 1].to_owned() &&
          a.name == (if kind == "image" { "embed" } else { "id" })
        })
        .unwrap()
      let relation = self
        .relationships()
        .iter()
        .find_first(link => {
          link.owner == drawing &&
          !link.external &&
          link.kind == relationship_uri + kind &&
          link.target == part
        })
        .map(link => link.id)
        .unwrap_or_else(() => {
          self.attach_sheet_resource(
            drawing, part, kind, mime, parts, created, edits,
          )
        })
      changes.push({
        node: node.id,
        offset: attr.start - node.start,
        length: attr.end - attr.start,
        xml: escaped_attribute(relation),
      })
      if kind == "chart" {
        let path = workbook_relations(object.part)
        let path = self.opc.names.get(path.to_lower()).unwrap_or(path)
        let document = parts.get(path).unwrap_or_else(() => self.part_xml(path))
        let tree = Tree::new(document)
        let link = document
          .nodes()
          .iter()
          .find_first(node => {
            node.name == "Relationship" &&
            node.attribute("Id") == Some(attr.value)
          })
          .unwrap()
        let raw = document.source()[link.start:link.end]
        guard !raw.contains("<!--") && !raw.contains("<?") else {
          @failure.reject(
            "protected-content", "Drawing relationship annotations require migration support",
          )
        }
        let (document, edit) = document.edit_source([
          sheet_node_removal(tree, link),
        ])
        parts[path] = document
        edits.push((path, edit))
        let original = self.part_xml(part)
        let tree = Tree::new(original)
        let references : Array[@xml.SourceChange] = []
        for node in original.nodes() {
          if node.uri != chart_uri ||
            node.name != "f" ||
            broken_chart_reference(node.text) {
            continue
          }
          if parse_formula(node.text) is Reference(None, first, last) {
            references.append(
              axis_text_change(
                tree,
                node,
                Expression::Reference(Some(source.name), first, last).source(),
              ),
            )
          }
        }
        if !references.is_empty() {
          let (document, edit) = original.edit_source(references)
          parts[part] = document
          edits.push((part, edit))
        }
      }
    }
  }
  let (copy, _) = object.tree.document.edit_source(changes)
  let markup = Tree::new(copy).picture_markup(object.frame.id)
  let (document, edit) = object.tree.document.edit_source([
    sheet_node_removal(object.tree, object.frame),
  ])
  parts[object.part] = document
  edits.push((object.part, edit))
  let document = parts.get(drawing).unwrap_or_else(() => self.part_xml(drawing))
  let (document, edit) = document.edit_source([
    insertion(document.nodes()[0], markup),
  ])
  parts[drawing] = document
  edits.push((drawing, edit))
  let sheets = self.sheets.copy()
  sheets[target_index] = Sheet::read(
    target_sheet,
    target.name,
    target.state,
    sheet_document,
    self.strings,
    self.styles.length(),
  )
  let candidate = { ..self, sheets, parts, }
  ignore(
    candidate.sheet_objects(sheets[self.sheet_index(source_sheet)], before),
  )
  ignore(candidate.sheet_objects(sheets[target_index], dimensions))
  self.commit(
    sheets,
    self.workbook,
    self.calculation.unwrap(),
    edits,
    (target_sheet, range),
    parts~,
    created_parts=created,
    drawing_selection=Some((target_sheet, next_id)),
  )
  self.query()
}
