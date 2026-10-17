///|
fn Session::write_image(
  self : Session,
  bytes : Bytes,
  placement : (Double, Double, Double, Double)?,
  fill~ : Bool = false,
  mode~ : String = "stretch",
  background~ : Int? = None,
  background_format~ : (Array[Double], Double)? = None,
) -> Json raise @failure.Failure {
  let original = background
    .map(i => self.slides[i])
    .unwrap_or_else(() => self.current())
  let (old_crop, old_opacity, old_tile) = if original.background
    is Picture(_, crop, opacity, tile) {
    (crop, opacity, tile)
  } else {
    ([0.0, 0.0, 0.0, 0.0], 1.0, None)
  }
  let (crop, opacity) = background_format.unwrap_or((old_crop, old_opacity))
  if background is Some(_) {
    check_image_fill_mode(mode)
    let reason = self.background_reason(original)
    guard reason.is_empty() else {
      @failure.reject("protected-content", reason)
    }
  }
  let targets = if fill { self.image_fill_targets() } else { [] }
  let target = if placement is None && !fill && background is None {
    Some(self.selected_image(false))
  } else {
    None
  }
  let (x, y, width, height) = placement.unwrap_or((0, 0, 1, 1))
  if placement is Some(_) {
    validate_object_box(x, y, width, height, false)
  }
  let (extension, content_type, _, _) = @image.type_info(bytes)
  if target is Some(object) && self.image_bytes(object.image.unwrap()) == bytes {
    return self.query()
  }
  if fill &&
    targets.all(object => {
      object.image is Some(key) &&
      self.image_bytes(key) == bytes &&
      (if object.tile is Some(_) { "tile" } else { "stretch" }) == mode &&
      object.source
      .child("spPr", uri=presentation_uri)
      .bind(p => p.child("blipFill"))
      is Some(_) &&
      !flag(object.source.node, "useBgFill")
    }) {
    return self.query()
  }
  let reuse = if background is Some(_) &&
    original.background is Picture(key, _, _, _) &&
    self.image_bytes(key) == bytes {
    Some(key)
  } else {
    None
  }
  if reuse is Some(_) &&
    background_image_source(original) is Some(_) &&
    crop == old_crop &&
    opacity == old_opacity &&
    (if old_tile is Some(_) { "tile" } else { "stretch" }) == mode {
    return self.query()
  }
  let identity = if target is Some(object) {
    object.id[original.tree.part.length() + 1:].to_owned()
  } else if targets.get(0) is Some(object) {
    object.id[original.tree.part.length() + 1:].to_owned()
  } else if background is Some(_) {
    "Background"
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
    path = reuse.unwrap_or(
      directory + "media/image\{identity}_\{sequence}.\{extension}",
    )
    link = "odImage\{identity}_\{sequence}"
    if (
        reuse is Some(_) ||
        (
          !self.opc.names.contains(path.to_lower()) &&
          !self.media.contains(path) &&
          !self.parts.contains(path)
        )
      ) &&
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
  if reuse is None {
    media[path] = bytes
  }
  let created_parts : Map[String, @xml.Document] = Map([])
  let edits : Array[(String, @xml.Edit)] = []
  let reused_link = if reuse is Some(_) {
    links
    .iter()
    .find_first(r => {
      r.owner == original.tree.part &&
      r.target == path &&
      r.kind == relationship_uri + "/image" &&
      !r.external
    })
    .map(r => r.id)
  } else {
    None
  }
  if reused_link is Some(id) {
    link = id
  }
  if reused_link is None {
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
  }
  if reuse is None {
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
  }
  let markup = "<p:pic xmlns:p=\"\{presentation_uri}\" xmlns:a=\"\{drawing_uri}\" xmlns:r=\"\{relationship_uri}\"><p:nvPicPr><p:cNvPr id=\"\{identity}\" name=\"Picture \{identity}\"/><p:cNvPicPr><a:picLocks noChangeAspect=\"1\"/></p:cNvPicPr><p:nvPr/></p:nvPicPr><p:blipFill><a:blip r:embed=\"\{link}\"/><a:stretch><a:fillRect/></a:stretch></p:blipFill><p:spPr><a:xfrm><a:off x=\"\{(x * 12700).round().to_int64()}\" y=\"\{(y * 12700).round().to_int64()}\"/><a:ext cx=\"\{(width * 12700).round().to_int64()}\" cy=\"\{(height * 12700).round().to_int64()}\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></p:spPr></p:pic>"
  let changes : Array[@xml.SourceChange] = []
  if background is Some(_) {
    if background_image_source(original) is Some(fill) {
      let blip = fill.child("blip").unwrap()
      let embed = blip.node.attributes
        .iter()
        .find_first(a => a.uri == relationship_uri && a.name == "embed")
        .unwrap()
      if embed.value != link {
        changes.push({
          node: blip.node.id,
          offset: embed.start - blip.node.start,
          length: embed.end - embed.start,
          xml: xml_attribute(link),
        })
      }
      if (if old_tile is Some(_) { "tile" } else { "stretch" }) != mode {
        changes.push(image_fill_mode_change(fill, mode))
      }
      if crop != old_crop {
        changes.push(image_crop_change(fill, crop))
      }
      if opacity != old_opacity {
        changes.push(
          image_opacity_change(blip, (opacity * 100000).round().to_int()),
        )
      }
    } else {
      changes.push(
        background_change(
          original,
          Some(
            image_fill_markup(
              link,
              opacity,
              crop,
              if mode == "tile" {
                Some(old_tile.unwrap_or(ImageTile::default()))
              } else {
                None
              },
            ),
          ),
        ),
      )
    }
  } else if fill {
    for object in targets {
      let properties = object.source
        .child("spPr", uri=presentation_uri)
        .unwrap()
      let crop = if object.image is Some(_) {
        object.crop
      } else {
        [0.0, 0.0, 0.0, 0.0]
      }
      if mode == "stretch" {
        let geometry = object.geometry.unwrap()
        check_image_crop_bounds(geometry.width, geometry.height, crop)
      }
      changes.push(
        paint_child_change(
          properties,
          paint_fill(properties),
          image_fill_markup(
            link,
            object.fill_alpha,
            crop,
            if mode == "tile" {
              Some(object.tile.unwrap_or(ImageTile::default()))
            } else {
              None
            },
          ),
          ["ln", "effectLst", "effectDag", "scene3d", "sp3d", "extLst"],
        ),
      )
      if flag(object.source.node, "useBgFill") {
        changes.push(attribute_change(object.source, "useBgFill", "0"))
      }
    }
  } else if target is Some(object) {
    let blip = object.source
      .child("blipFill", uri=presentation_uri)
      .unwrap()
      .child("blip")
      .unwrap()
    let embed = blip.node.attributes
      .iter()
      .find_first(a => a.uri == relationship_uri && a.name == "embed")
      .unwrap()
    changes.push({
      node: blip.node.id,
      offset: embed.start - blip.node.start,
      length: embed.end - embed.start,
      xml: link,
    })
  } else {
    changes.push(object_insertion(original.tree, markup))
  }
  let (document, edit) = original.tree.document.edit_source(changes)
  let candidate = read_slide(
    self.opc,
    self.main,
    self.cache,
    Tree::new(original.tree.part, document),
    index=self.index(original.tree.part),
    parts~,
  )
  edits.push((original.tree.part, edit))
  let slides = self.slides.copy()
  slides[self.index(original.tree.part)] = candidate
  let id = original.tree.part + "#" + identity
  let after : Selection = if target is Some(_) || fill || background is Some(_) {
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
    created_media=if reuse is None { Map([(path, bytes)]) } else { Map([]) },
  )
  if target is None && !fill && background is None {
    self.object_sequence = number(identity, 0, 4294967295).to_int64() + 1L
  }
  self.query()
}
