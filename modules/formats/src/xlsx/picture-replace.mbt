///|
/// Replace a picture's image resource while preserving its native frame and metadata.
pub fn Session::replace_picture(
  self : Session,
  revision : Int,
  sheet : String,
  id : String,
  bytes : Bytes,
  probe : @layout.TextProbe,
  profile : Map[String, String],
  images? : @layout.Images,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  guard bytes.length() <= 2097152 else {
    @failure.reject("limit-exceeded", "Worksheet image input exceeds 2 MiB")
  }
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
  picture.check_change(false)
  let (part, mime) = self.new_picture_part(bytes)
  if self.picture_bytes(picture.media.unwrap()) == bytes {
    return self.query()
  }
  if images is Some(images) {
    let decoded = images.get(picture_key(part))
    let (_, _, width, height) = @image.type_info(bytes)
    guard decoded.width == width && decoded.height == height else {
      @failure.reject(
        "missing-image", "Decoded worksheet picture dimensions differ",
      )
    }
  }
  let parts = self.parts.copy()
  let created : Map[String, @xml.Document] = Map([])
  let edits : Array[(String, @xml.Edit)] = []
  let relation = self.attach_sheet_resource(
    picture.part,
    part,
    "image",
    mime,
    parts,
    created,
    edits,
  )
  let tree = picture.tree
  let fill = tree.picture_node(picture.source.id, "blipFill")
  let blip = tree.picture_node(fill.id, "blip", uri=picture_drawing_uri)
  let attribute = blip.attributes
    .iter()
    .find_first(a => {
      a.name == "embed" &&
      a.uri == relationship_uri[:relationship_uri.length() - 1].to_owned()
    })
    .unwrap()
  let (document, edit) = tree.document.edit_source([
    {
      node: blip.id,
      offset: attribute.start - blip.start,
      length: attribute.end - attribute.start,
      xml: escaped_attribute(relation),
    },
  ])
  parts[picture.part] = document
  edits.push((picture.part, edit))
  let media = self.media.copy()
  media[part] = bytes
  let candidate = { ..self, parts, media, }
  ignore(candidate.sheet_pictures(current, dimensions))
  self.commit(
    self.sheets,
    self.workbook,
    self.calculation.unwrap(),
    edits,
    self.selection,
    parts~,
    created_parts=created,
    media~,
    added_media=Map([(part, bytes)]),
    drawing_selection=self.drawing_selection,
    font_context=Some((probe, profile.copy())),
  )
  self.query()
}
