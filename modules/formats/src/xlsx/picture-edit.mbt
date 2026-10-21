///|
pub fn Session::insert_picture(
  self : Session,
  revision : Int,
  sheet : String,
  width : Double,
  height : Double,
  bytes : Bytes,
  probe : @layout.TextProbe,
  profile : Map[String, String],
  name~ : String = "Picture",
  description~ : String = "",
  images? : @layout.Images,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let index = self.sheet_index(sheet)
  let current = self.sheets[index]
  let reason = self.dimension_reason(current)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  check_picture_text(name, description)
  let dimensions = self.resolved_dimensions(current, probe, profile)
  let pictures = self.sheet_pictures(current, dimensions)
  guard pictures.length() < 256 else {
    @failure.reject("limit-exceeded", "Worksheet picture count exceeds256")
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
  check_picture_rect("move", rect, dimensions)
  let (media_part, mime) = self.new_picture_part(bytes)
  if images is Some(images) {
    let decoded = images.get(picture_key(media_part))
    let (_, _, width, height) = @image.type_info(bytes)
    guard decoded.width == width && decoded.height == height else {
      @failure.reject(
        "missing-image", "Decoded worksheet picture dimensions differ",
      )
    }
  }
  let identity = for i in 1..<=16384 {
    if !pictures.any(p => p.id == i.to_string()) {
      break i.to_string()
    }
  } nobreak {
    @failure.reject("limit-exceeded", "Worksheet picture identities exhausted")
  }
  let parts = self.parts.copy()
  let media = self.media.copy()
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
  let relation = self.attach_sheet_resource(
    drawing, media_part, "image", mime, parts, created, edits,
  )
  media[media_part] = bytes
  let picture = "<odXdr:pic xmlns:odXdr=\"\{picture_uri}\" xmlns:odA=\"\{picture_drawing_uri}\" xmlns:odR=\"\{relationship_uri[:relationship_uri.length()-1]}\"><odXdr:nvPicPr><odXdr:cNvPr id=\"\{identity}\" name=\"\{escaped_attribute(name)}\" descr=\"\{escaped_attribute(description)}\"/><odXdr:cNvPicPr><odA:picLocks noChangeAspect=\"1\"/></odXdr:cNvPicPr></odXdr:nvPicPr><odXdr:blipFill><odA:blip odR:embed=\"\{relation}\"/><odA:stretch><odA:fillRect/></odA:stretch></odXdr:blipFill><odXdr:spPr>\{picture_transform(rect)}<odA:prstGeom prst=\"rect\"><odA:avLst/></odA:prstGeom></odXdr:spPr></odXdr:pic>"
  let document = parts.get(drawing).unwrap_or_else(() => self.part_xml(drawing))
  let (document, edit) = document.edit_source([
    insertion(
      document.nodes()[0],
      picture_frame_source("move", rect, picture, dimensions),
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
  let candidate = { ..self, sheets, parts, media, }
  ignore(candidate.sheet_pictures(sheets[index], dimensions))
  self.commit(
    sheets,
    self.workbook,
    self.calculation.unwrap(),
    edits,
    self.selection,
    parts~,
    created_parts=created,
    media~,
    added_media=Map([(media_part, bytes)]),
    font_context=Some((probe, profile.copy())),
  )
  self.query()
}

///|
fn Picture::check_change(
  self : Picture,
  remove : Bool,
  rect? : @layout.Border,
) -> Unit raise @failure.Failure {
  for node in self.tree.document.nodes() {
    if node.start < self.source.start ||
      node.end > self.source.end ||
      !node.name.has_suffix("Locks") {
      continue
    }
    guard !flag(node, "noSelect") &&
      (
        remove ||
        rect
        .map(r => {
          (r.x == self.rect.x && r.y == self.rect.y) || !flag(node, "noMove")
        })
        .unwrap_or(true)
      ) &&
      (
        remove ||
        rect
        .map(r => {
          (r.width == self.rect.width && r.height == self.rect.height) ||
          !flag(node, "noResize")
        })
        .unwrap_or(true)
      ) else {
      @failure.reject(
        "protected-content", "Worksheet picture changes are locked",
      )
    }
    if !remove && flag(node, "noChangeAspect") && rect is Some(rect) {
      guard (rect.width * self.rect.height - rect.height * self.rect.width).abs() <=
        0.01 else {
        @failure.reject(
          "protected-content", "Worksheet picture aspect ratio is locked",
        )
      }
    }
  }
}

///|
pub fn Session::set_picture(
  self : Session,
  revision : Int,
  sheet : String,
  id : String,
  anchor : String,
  rect : @layout.Border,
  name : String,
  description : String,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let current = self.sheets[self.sheet_index(sheet)]
  let reason = self.dimension_reason(current)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  check_picture_text(name, description)
  let dimensions = self.resolved_dimensions(current, probe, profile)
  check_picture_rect(anchor, rect, dimensions)
  let picture = self
    .sheet_pictures(current, dimensions)
    .iter()
    .find_first(p => p.id == id)
    .unwrap_or_else(() => {
      @failure.reject("invalid-operation", "Worksheet picture no longer exists")
    })
  picture.check_change(false, rect~)
  if picture.anchor == anchor &&
    picture.rect.x == rect.x &&
    picture.rect.y == rect.y &&
    picture.rect.width == rect.width &&
    picture.rect.height == rect.height &&
    picture.name == name &&
    picture.description == description {
    return self.query()
  }
  let tree = picture.tree
  let nv = tree.picture_node(picture.source.id, "nvPicPr")
  let identity = tree.picture_node(nv.id, "cNvPr")
  let changes = metadata_changes(identity, [
    ("name", name),
    ("descr", description),
  ])
  changes.push(picture.transform_change(rect))
  let (document, style_edit) = tree.document.edit_source(changes)
  let markup = Tree::new(document).picture_markup(picture.source.id)
  let next = Tree::new(document)
  let frame = next.nodes[picture.frame.id]
  let client_data = next
    .picture_child(frame.id, "clientData")
    .map(node => next.picture_markup(node.id))
    .unwrap_or("<odXdr:clientData/>")
  let (document, frame_edit) = document.edit_source([
    {
      node: frame.parent,
      offset: frame.start - next.nodes[frame.parent].start,
      length: frame.end - frame.start,
      xml: picture_frame_source(anchor, rect, markup, dimensions, client_data~),
    },
  ])
  let parts = self.parts.copy()
  parts[picture.part] = document
  let candidate = { ..self, parts, }
  ignore(candidate.sheet_pictures(current, dimensions))
  self.commit(
    self.sheets,
    self.workbook,
    self.calculation.unwrap(),
    [(picture.part, style_edit), (picture.part, frame_edit)],
    self.selection,
    parts~,
    font_context=Some((probe, profile.copy())),
  )
  self.query()
}

///|
pub fn Session::delete_picture(
  self : Session,
  revision : Int,
  sheet : String,
  id : String,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let current = self.sheets[self.sheet_index(sheet)]
  let reason = self.dimension_reason(current)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let dimensions = self.resolved_dimensions(current, probe, profile)
  let picture = self
    .sheet_pictures(current, dimensions)
    .iter()
    .find_first(p => p.id == id)
    .unwrap_or_else(() => {
      @failure.reject("invalid-operation", "Worksheet picture no longer exists")
    })
  picture.check_change(true)
  let (document, edit) = picture.tree.document.edit_source([
    sheet_node_removal(picture.tree, picture.frame),
  ])
  let parts = self.parts.copy()
  parts[picture.part] = document
  self.commit(
    self.sheets,
    self.workbook,
    self.calculation.unwrap(),
    [(picture.part, edit)],
    self.selection,
    parts~,
  )
  self.query()
}
