///|
pub fn Session::insert_shape(
  self : Session,
  revision : Int,
  sheet : String,
  kind : String,
  width : Double,
  height : Double,
  text : String,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let index = self.sheet_index(sheet)
  let current = self.sheets[index]
  let reason = self.dimension_reason(current)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let dimensions = self.resolved_dimensions(current, probe, profile)
  let objects = self.sheet_objects(current, dimensions)
  guard objects.length() < 256 else {
    @failure.reject("limit-exceeded", "Worksheet drawings exceed 256 entries")
  }
  let range = if self.selection.0 == sheet {
    self.selection.1
  } else {
    Range::parse("A1")
  }
  let rect : @layout.Border = {
    x: dimensions.columns.position(range.left),
    y: dimensions.rows.position(range.top),
    width,
    height,
  }
  let settings : ShapeSettings = {
    kind,
    anchor: "move",
    rect,
    name: if kind == "textBox" {
      "Text Box"
    } else {
      "Shape"
    },
    description: "",
    fill: if ["textBox", "line"].contains(kind) {
      None
    } else {
      Some(self.theme[4])
    },
    stroke: if kind == "textBox" {
      None
    } else {
      Some("000000")
    },
    line_width: 1,
    text,
    font: self.normal_font,
    bold: false,
    italic: false,
    size: 12,
    color: "000000",
    wrap: true,
    align: "left",
    vertical: "top",
    insets: [7.2, 3.6, 7.2, 3.6],
  }
  let shape = settings.checked(dimensions)
  let preview : Array[@layout.PositionedPrimitive] = []
  shape.paint(preview, rect, probe, profile)
  let id = for i in 1..<=16384 {
    if !objects.any(object => object.id == i.to_string()) {
      break i.to_string()
    }
  } nobreak {
    @failure.reject("limit-exceeded", "Worksheet drawing identities exhausted")
  }
  let parts = self.parts.copy()
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
  let nv = "<odXdr:nvSpPr><odXdr:cNvPr id=\"\{id}\" name=\"\{escaped_attribute(settings.name)}\"/><odXdr:cNvSpPr txBox=\"\{if shape.text_box { 1 } else { 0 }}\"/></odXdr:nvSpPr>"
  let document = parts.get(drawing).unwrap_or_else(() => self.part_xml(drawing))
  let (document, edit) = document.edit_source([
    insertion(
      document.nodes()[0],
      picture_frame_source("move", rect, shape.source(rect, nv), dimensions),
    ),
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
  let candidate = { ..self, sheets, parts, }
  ignore(candidate.sheet_objects(sheets[index], dimensions))
  self.commit(
    sheets,
    self.workbook,
    self.calculation.unwrap(),
    edits,
    self.selection,
    parts~,
    created_parts=created,
    drawing_selection=Some((sheet, id)),
    font_context=Some((probe, profile.copy())),
  )
  self.query()
}

///|
pub fn Session::set_shape(
  self : Session,
  revision : Int,
  sheet : String,
  id : String,
  settings : ShapeSettings,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let current = self.sheets[self.sheet_index(sheet)]
  let reason = self.dimension_reason(current)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let dimensions = self.resolved_dimensions(current, probe, profile)
  let shape = settings.checked(dimensions)
  let object = self
    .sheet_objects(current, dimensions)
    .iter()
    .find_first(object => object.id == id && object.shape is Some(_))
    .unwrap_or_else(() => {
      @failure.reject("invalid-operation", "Worksheet shape no longer exists")
    })
  object.check_change(false, rect=settings.rect)
  object.check_shape_locks(shape)
  if object.shape == Some(shape) &&
    object.anchor == settings.anchor &&
    (object.rect.x, object.rect.y, object.rect.width, object.rect.height) ==
    (
      settings.rect.x,
      settings.rect.y,
      settings.rect.width,
      settings.rect.height,
    ) &&
    object.name == settings.name &&
    object.description == settings.description {
    return self.query()
  }
  object.check_shape_source()
  let preview : Array[@layout.PositionedPrimitive] = []
  shape.paint(preview, settings.rect, probe, profile)
  let nv = object.tree.picture_node(object.source.id, "nvSpPr")
  let identity = object.tree.picture_node(nv.id, "cNvPr")
  let properties = object.tree.picture_node(nv.id, "cNvSpPr")
  let changes = metadata_changes(identity, [
    ("name", settings.name),
    ("descr", settings.description),
  ])
  changes.append(
    metadata_changes(properties, [
      ("txBox", if shape.text_box { "1" } else { "0" }),
    ]),
  )
  let (document, metadata) = object.tree.document.edit_source(changes)
  let next = Tree::new(document)
  let nv_markup = next.picture_markup(nv.id)
  let frame = next.nodes[object.frame.id]
  let client_data = next
    .picture_child(frame.id, "clientData")
    .map(node => next.picture_markup(node.id))
    .unwrap_or("<odXdr:clientData/>")
  let (document, edit) = document.edit_source([
    {
      node: frame.parent,
      offset: frame.start - next.nodes[frame.parent].start,
      length: frame.end - frame.start,
      xml: picture_frame_source(
        settings.anchor,
        settings.rect,
        shape.source(settings.rect, nv_markup),
        dimensions,
        client_data~,
      ),
    },
  ])
  let parts = self.parts.copy()
  parts[object.part] = document
  let candidate = { ..self, parts, }
  ignore(candidate.sheet_objects(current, dimensions))
  self.commit(
    self.sheets,
    self.workbook,
    self.calculation.unwrap(),
    [(object.part, metadata), (object.part, edit)],
    self.selection,
    parts~,
    drawing_selection=self.drawing_selection,
    font_context=Some((probe, profile.copy())),
  )
  self.query()
}
