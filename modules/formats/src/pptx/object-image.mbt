///|
fn Session::write_image(
  self : Session,
  bytes : Bytes,
  placement : (Double, Double, Double, Double)?,
) -> Json raise @failure.Failure {
  let target = if placement is None {
    Some(self.selected_image(false))
  } else {
    None
  }
  let (x, y, width, height) = placement.unwrap_or((0, 0, 1, 1))
  if placement is Some(_) {
    validate_object_box(x, y, width, height, false)
  }
  let (extension, content_type) = image_type(bytes)
  if target is Some(object) && self.image_bytes(object.image.unwrap()) == bytes {
    return self.query()
  }
  let original = self.current()
  let identity = if target is Some(object) {
    object.id[original.tree.part.length() + 1:].to_owned()
  } else {
    self.next_object_identity()
  }
  let segments = self.main.part.split("/").map(s => s.to_owned()).to_array()
  ignore(segments.pop())
  let directory = if segments.is_empty() {
    ""
  } else {
    segments.join("/") + "/"
  }
  let mut sequence = 1
  let mut path = ""
  let mut link = ""
  let links = self.relationships()
  while true {
    path = directory + "media/image\{identity}_\{sequence}.\{extension}"
    link = "odImage\{identity}_\{sequence}"
    if !self.opc.names.contains(path.to_lower()) &&
      !self.media.contains(path) &&
      !self.parts.contains(path) &&
      !links
      .iter()
      .any(rel => rel.owner == original.tree.part && rel.id == link) {
      break
    }
    guard sequence < 16384 else {
      @failure.reject("limit-exceeded", "Image identities exhausted")
    }
    sequence += 1
  }
  let parts = self.parts.copy()
  let media = self.media.copy()
  media[path] = bytes
  let created_parts : Map[String, @xml.Document] = Map([])
  let edits : Array[(String, @xml.Edit)] = []
  let relations_path = relationship_part(original.tree.part)
  let relations = parts
    .get(relations_path)
    .unwrap_or_else(() => {
      if self.opc.names.contains(relations_path.to_lower()) {
        self.opc.xml(relations_path)
      } else {
        @xml.Document::parse(
          b"<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"/>",
          relations_path,
          self.budget.xml_depth,
          self.budget.entry_bytes,
        )
      }
    })
  let (relations, edit) = relations.edit_source([
    insertion(
      relations.nodes()[0],
      "<Relationship xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\" Id=\"\{link}\" Type=\"\{relationship_uri}/image\" Target=\"/\{xml_attribute(path)}\"/>",
    ),
  ])
  parts[relations_path] = relations
  if !self.parts.contains(relations_path) &&
    !self.opc.names.contains(relations_path.to_lower()) {
    created_parts[relations_path] = relations
  } else {
    edits.push((relations_path, edit))
  }
  let types_path = "[Content_Types].xml"
  let types = parts
    .get(types_path)
    .unwrap_or_else(() => self.opc.xml(types_path))
  let (types, edit) = types.edit_source([
    insertion(
      types.nodes()[0],
      "<Override xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\" PartName=\"/\{xml_attribute(path)}\" ContentType=\"\{content_type}\"/>",
    ),
  ])
  parts[types_path] = types
  edits.push((types_path, edit))
  let markup = "<p:pic xmlns:p=\"\{presentation_uri}\" xmlns:a=\"\{drawing_uri}\" xmlns:r=\"\{relationship_uri}\"><p:nvPicPr><p:cNvPr id=\"\{identity}\" name=\"Picture \{identity}\"/><p:cNvPicPr><a:picLocks noChangeAspect=\"1\"/></p:cNvPicPr><p:nvPr/></p:nvPicPr><p:blipFill><a:blip r:embed=\"\{link}\"/><a:stretch><a:fillRect/></a:stretch></p:blipFill><p:spPr><a:xfrm><a:off x=\"\{(x * 12700).round().to_int64()}\" y=\"\{(y * 12700).round().to_int64()}\"/><a:ext cx=\"\{(width * 12700).round().to_int64()}\" cy=\"\{(height * 12700).round().to_int64()}\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></p:spPr></p:pic>"
  let change : @xml.SourceChange = if target is Some(object) {
    let blip = object.source
      .child("blipFill", uri=presentation_uri)
      .unwrap()
      .child("blip")
      .unwrap()
    let embed = blip.node.attributes
      .iter()
      .find_first(a => a.uri == relationship_uri && a.name == "embed")
      .unwrap()
    {
      node: blip.node.id,
      offset: embed.start - blip.node.start,
      length: embed.end - embed.start,
      xml: link,
    }
  } else {
    object_insertion(original.tree, markup)
  }
  let (document, edit) = original.tree.document.edit_source([change])
  let candidate = read_slide(
    self.opc,
    self.main,
    self.cache,
    Tree::new(original.tree.part, document),
    parts~,
  )
  edits.push((original.tree.part, edit))
  let slides = self.slides.copy()
  slides[self.index(original.tree.part)] = candidate
  let images : Map[String, Bool] = Map([])
  for slide in slides {
    for object in slide.objects {
      if object.image is Some(key) {
        images[key] = true
      }
    }
  }
  guard images.length() <= 256 else {
    @failure.reject("limit-exceeded", "Presentation images exceed 256")
  }
  let id = original.tree.part + "#" + identity
  let after : Selection = if target is Some(_) {
    self.selection
  } else {
    {
      ..self.selection,
      object: id,
      objects: [id],
      mode: "object",
      anchor: 0,
      focus: 0,
    }
  }
  self.commit_slides(
    self.main,
    slides,
    edits,
    after,
    parts~,
    media~,
    created_parts~,
    created_media=Map([(path, bytes)]),
  )
  if target is None {
    self.object_sequence = number(identity, 0, 4294967295).to_int64() + 1L
  }
  self.query()
}
