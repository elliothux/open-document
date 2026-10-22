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
  let (copy, _) = object.tree.document.edit_source(changes)
  let markup = Tree::new(copy).picture_markup(object.frame.id)
  let document = parts.get(drawing).unwrap_or_else(() => self.part_xml(drawing))
  let (document, edit) = document.edit_source([
    insertion(document.nodes()[0], markup),
  ])
  parts[drawing] = document
  edits.push((drawing, edit))
  let sheets = self.sheets.copy()
  sheets[index] = Sheet::read(
    sheet,
    current.name,
    current.state,
    sheet_document,
    self.strings,
    self.styles.length(),
  )
  let candidate = { ..self, sheets, parts, media, }
  ignore(candidate.sheet_objects(sheets[index], dimensions))
  self.commit(
    sheets,
    self.workbook,
    self.calculation.unwrap(),
    edits,
    (sheet, range),
    parts~,
    created_parts=created,
    media~,
    added_media~,
    drawing_selection=Some((sheet, id)),
    font_context=Some((probe, profile.copy())),
  )
  self.query()
}
