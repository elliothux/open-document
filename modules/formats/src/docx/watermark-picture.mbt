///|
fn picture_watermark_markup(
  identity : String,
  link : String,
  width : Double,
  height : Double,
  opacity : Double,
) -> String raise @failure.Failure {
  let cx = (width * 12700).round().to_int64()
  let cy = (height * 12700).round().to_int64()
  let link = property_attribute(link)
  let picture = "http://schemas.openxmlformats.org/drawingml/2006/picture"
  "<w:sdt xmlns:w='\{word_uri}' xmlns:wp='\{picture_inline_uri}' xmlns:a='\{picture_drawing_uri}' xmlns:pic='\{picture}' xmlns:r='\{running_rel_uri}'><w:sdtPr><w:docPartObj><w:docPartGallery w:val='Watermarks'/><w:docPartUnique/></w:docPartObj></w:sdtPr><w:sdtContent><w:p><w:r><w:drawing><wp:anchor simplePos='0' relativeHeight='0' behindDoc='1' locked='0' layoutInCell='0' allowOverlap='1' distT='0' distB='0' distL='0' distR='0'><wp:simplePos x='0' y='0'/><wp:positionH relativeFrom='margin'><wp:align>center</wp:align></wp:positionH><wp:positionV relativeFrom='margin'><wp:align>center</wp:align></wp:positionV><wp:extent cx='\{cx}' cy='\{cy}'/><wp:wrapNone/><wp:docPr id='\{identity}' name='Picture watermark'/><a:graphic><a:graphicData uri='\{picture}'><pic:pic><pic:nvPicPr><pic:cNvPr id='\{identity}' name='Picture watermark'/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed='\{link}'><a:alphaModFix amt='\{(opacity*100000).round().to_int()}'/></a:blip><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x='0' y='0'/><a:ext cx='\{cx}' cy='\{cy}'/></a:xfrm><a:prstGeom prst='rect'/></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:anchor></w:drawing></w:r></w:p></w:sdtContent></w:sdt>"
}

///|
fn WordTree::picture_watermark_source(
  self : WordTree,
  id : Int,
) -> WatermarkSource raise @failure.Failure {
  let extent = self.watermark_node(id, "extent", uri=picture_inline_uri)
  let width = watermark_number(extent, "cx") / 12700
  let height = watermark_number(extent, "cy") / 12700
  let opacity = watermark_number(
      self.watermark_node(id, "alphaModFix", uri=picture_drawing_uri),
      "amt",
    ) /
    100000
  let link = self
    .watermark_node(id, "blip", uri=picture_drawing_uri)
    .attribute("embed", uri=running_rel_uri)
    .unwrap_or("")
  guard !link.is_empty() else {
    @failure.reject(
      "protected-content", "Missing picture watermark relationship",
    )
  }
  let identity = self
    .watermark_node(id, "docPr", uri=picture_inline_uri)
    .attribute("id")
    .unwrap_or("")
  let value = Watermark::Picture(Resource(link), width, height, opacity).normalized()
  let expected = WordTree::new(
    @xml.Document::parse(
      @utf8.encode(
        picture_watermark_markup(identity, link, width, height, opacity),
      ),
      "watermark",
      64,
      history_byte_limit,
    ),
  )
  let source = self.source[self.nodes[id].start:self.nodes[id].end]
  guard !source.contains("<!--") &&
    !source.contains("<?") &&
    watermark_equal(self, id, expected, 0) else {
    @failure.reject(
      "protected-content", "Extended picture watermark is protected",
    )
  }
  { node: id, identity, value, }
}

///|
fn Session::watermark_value(
  self : Session,
  owner : String,
  value : Watermark,
) -> Watermark raise @failure.Failure {
  match value {
    Text(_) => value
    Picture(Resource(id), width, height, opacity) => {
      guard self
        .relationships()
        .iter()
        .find_first(r => {
          r.owner == owner && r.id == id && r.kind == running_rel_uri + "/image"
        })
        is Some(link) &&
        !link.external else {
        @failure.reject(
          "protected-content", "Picture watermarks require an internal header image",
        )
      }
      Picture(Resource("watermark:" + link.target), width, height, opacity)
    }
    _ =>
      @failure.reject("invalid-operation", "Expected a stored watermark image")
  }
}

///|
fn Session::watermark_image_link(
  self : Session,
  owner : String,
  path : String,
  parts : Map[String, @xml.Document],
  edits : Map[String, Array[@xml.Edit]],
  created : Map[String, @xml.Document],
) -> String raise @failure.Failure {
  let view = { ..self, parts, }
  let links = view.relationships()
  if links
    .iter()
    .find_first(r => {
      r.owner == owner &&
      !r.external &&
      r.kind == running_rel_uri + "/image" &&
      r.target == path
    })
    is Some(link) {
    return link.id
  }
  let id = for i = 1; i <= 16384; i = i + 1 {
    let id = "odWatermark\{i}"
    if !links.any(r => r.owner == owner && r.id == id) {
      break id
    }
  } nobreak {
    @failure.reject(
      "limit-exceeded", "Watermark relationship identities exhausted",
    )
  }
  let segments = owner.split("/").to_array()
  let directory = segments[:segments.length() - 1]
    .map(s => s.to_owned())
    .join("/")
  let relative = (if directory.is_empty() { "" } else { directory + "/" }) +
    "_rels/" +
    segments.last().unwrap().to_owned() +
    ".rels"
  let name = self.opc.names.get(relative.to_lower()).unwrap_or(relative)
  let markup = "<Relationship xmlns='http://schemas.openxmlformats.org/package/2006/relationships' Id='\{id}' Type='\{running_rel_uri}/image' Target='/\{property_attribute(path)}'/>"
  if self.opc.names.contains(name.to_lower()) || parts.contains(name) {
    let (document, edit) = append_part_xml(view.part_xml(name), markup)
    parts[name] = document
    if created.contains(name) {
      created[name] = document
    } else {
      edits.get_or_init(name, () => []).push(edit)
    }
  } else {
    let document = @xml.Document::parse(
      @utf8.encode(
        "<Relationships xmlns='http://schemas.openxmlformats.org/package/2006/relationships'>\{markup}</Relationships>",
      ),
      name,
      self.opc.budget.xml_depth,
      self.opc.budget.entry_bytes,
    )
    parts[name] = document
    created[name] = document
    self.ensure_relationship_type(name, parts, edits)
  }
  id
}
