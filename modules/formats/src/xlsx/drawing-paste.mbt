///|
fn Session::drawing_fragment_shape(
  self : Session,
  object : SheetObject,
) -> SheetObject raise @failure.Failure {
  guard object.shape is Some(shape) else { return object }
  let target = self.read_sheet_shape(
    object.part,
    object.tree,
    object.frame,
    object.source,
    drawing_fragment_dimensions(),
  )
  if target.shape == object.shape {
    return object
  }
  object.check_shape_source()
  let nv = object.tree.picture_node(object.source.id, "nvSpPr")
  let (document, _) = object.tree.document.edit_source([
    {
      node: object.frame.id,
      offset: object.source.start - object.frame.start,
      length: object.source.end - object.source.start,
      xml: shape.source(object.rect, object.tree.picture_markup(nv.id)),
    },
  ])
  let tree = Tree::new(document)
  self.read_sheet_shape(
    object.part,
    tree,
    tree.nodes[object.frame.id],
    tree.picture_node(object.frame.id, "sp"),
    drawing_fragment_dimensions(),
  )
}

///|
pub fn Session::paste_drawing(
  self : Session,
  revision : Int,
  sheet : String,
  fragment : String,
  probe : @layout.TextProbe,
  profile : Map[String, String],
  images? : @layout.Images,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let index = self.sheet_index(sheet)
  let current = self.sheets[index]
  let reason = self.dimension_reason(current)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let decoded = read_drawing_fragment(fragment, self.budget)
  let object = self.drawing_fragment_shape(decoded.object)
  let dimensions = self.resolved_dimensions(current, probe, profile)
  let objects = self.sheet_objects(current, dimensions)
  guard objects.length() < 256 else {
    @failure.reject("limit-exceeded", "Worksheet drawings exceed 256 entries")
  }
  let id = for index in 1..<=16384 {
    if !objects.any(object => object.id == index.to_string()) {
      break index.to_string()
    }
  } nobreak {
    @failure.reject("limit-exceeded", "Worksheet drawing identities exhausted")
  }
  let range = if self.selection.0 == sheet {
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
      "invalid-operation", "Pasted drawing would exceed the worksheet",
    )
  }
  if object.shape is Some(shape) {
    let preview : Array[@layout.PositionedPrimitive] = []
    shape.paint(preview, rect, probe, profile)
  }
  if object.chart is Some((_, chart)) {
    ignore(
      chart.data.paint(
        rect.width,
        rect.height,
        probe,
        profile,
        visible=object.chart_visibility,
      ),
    )
  }
  let changes = object.transfer_changes(
    object.transfer_identity(true),
    id,
    rect,
    dimensions,
  )
  let parts = self.parts.copy()
  let media = self.media.copy()
  let added_media : Map[String, Bytes] = Map([])
  let created : Map[String, @xml.Document] = Map([])
  let edits : Array[(String, @xml.Edit)] = []
  let sheets = self.sheets.copy()
  let mut workbook = self.workbook
  let mut created_sheet : Sheet? = None
  let mut next_sheet = self.next_sheet
  if decoded.data is Some(data) {
    let reason = self.sheet_edit_reason()
    guard reason.is_empty() else {
      @failure.reject("protected-content", reason)
    }
    let (added, number, markup, metadata) = self.prepare_sheet_add()
    let data = @xml.Document::parse(
      data.bytes(),
      added.id,
      self.budget.xml_depth,
      self.budget.entry_bytes,
    )
    let added = Sheet::read(
      added.id,
      added.name,
      "hidden",
      data,
      self.strings,
      self.styles.length(),
    )
    for (part, document, edit) in metadata {
      parts[part] = document
      edits.push((part, edit))
    }
    let tree = Tree::new(workbook)
    let parent = tree.one(tree.root("workbook").id, "sheets").unwrap()
    let (updated, edit) = workbook.edit_source([
      insertion(
        parent,
        markup.replace(old="state=\"visible\"", new="state=\"hidden\""),
      ),
    ])
    workbook = updated
    edits.push((self.main, edit))
    sheets.push(added)
    created_sheet = Some(added)
    next_sheet = number + 1
  }
  let (drawing, sheet_document) = match self.picture_drawing(current) {
    Some((part, _)) => (part, current.document)
    None => {
      let (part, relation) = self.create_sheet_resource(
        sheet,
        "drawing",
        "<xdr:wsDr xmlns:xdr=\"\{picture_uri}\"/>",
        parts,
        created,
        edits,
      )
      let (document, edit) = insert_sheet_drawing(
        current.document,
        relation,
        name="drawing",
      )
      edits.push((sheet, edit))
      (part, document)
    }
  }
  if decoded.image is Some(bytes) {
    let (part, mime) = self.new_picture_part(bytes)
    if images is Some(images) {
      let image = images.get(picture_key(part))
      let (_, _, width, height) = @image.type_info(bytes)
      guard image.width == width && image.height == height else {
        @failure.reject(
          "missing-image", "Decoded drawing clipboard image dimensions differ",
        )
      }
    }
    let relation = self.attach_sheet_resource(
      drawing, part, "image", mime, parts, created, edits,
    )
    let node = object.tree.document
      .nodes()
      .iter()
      .find_first(node => node.uri == picture_drawing_uri && node.name == "blip")
      .unwrap()
    let attribute = node.attributes[0]
    changes.push({
      node: node.id,
      offset: attribute.start - node.start,
      length: attribute.end - attribute.start,
      xml: escaped_attribute(relation),
    })
    media[part] = bytes
    added_media[part] = bytes
  }
  if object.chart is Some((_, chart)) {
    let added = created_sheet.unwrap()
    let document = @xml.Document::parse(
      @utf8.encode(chart.markup()),
      "chart.xml",
      self.budget.xml_depth,
      self.budget.entry_bytes,
    )
    let references = sheet_reference_changes(
      document,
      "Sheet1",
      Some(added.name),
      charts=true,
    )
    let source = if references.is_empty() {
      document.source()
    } else {
      document.edit_source(references).0.source()
    }
    let (_, relation) = self.create_sheet_resource(
      drawing, "chart", source, parts, created, edits,
    )
    let document = drawing_fragment_reference(
      object.tree.document,
      chart_uri,
      "chart",
      "id",
      relation,
    )
    let reference = document
      .nodes()
      .iter()
      .find_first(node => node.uri == chart_uri && node.name == "chart")
      .unwrap()
    let original = object.tree.nodes[reference.id]
    let attribute = original.attributes[0]
    changes.push({
      node: original.id,
      offset: attribute.start - original.start,
      length: attribute.end - attribute.start,
      xml: escaped_attribute(relation),
    })
  }
  let (copy, _) = object.tree.document.edit_source(changes)
  let markup = Tree::new(copy).picture_markup(object.frame.id)
  let document = parts.get(drawing).unwrap_or_else(() => self.part_xml(drawing))
  let (document, edit) = document.edit_source([
    insertion(document.nodes()[0], markup),
  ])
  parts[drawing] = document
  edits.push((drawing, edit))
  sheets[index] = Sheet::read(
    sheet,
    current.name,
    current.state,
    sheet_document,
    self.strings,
    self.styles.length(),
  )
  let calculation = if created_sheet is Some(_) {
    self.calculate(sheets, None, [], workbook, parts~)
  } else {
    self.calculation.unwrap()
  }
  let candidate = {
    ..self,
    sheets,
    workbook,
    parts,
    media,
    calculation: Some(calculation),
  }
  ignore(candidate.sheet_objects(sheets[index], dimensions))
  self.commit(
    sheets,
    workbook,
    calculation,
    edits,
    (sheet, range),
    parts~,
    created_parts=created,
    created=created_sheet,
    media~,
    added_media~,
    drawing_selection=Some((sheet, id)),
    font_context=Some((probe, profile.copy())),
  )
  self.next_sheet = next_sheet
  self.query()
}
