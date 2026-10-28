///|
fn xml_attribute(value : String) -> String raise @failure.Failure {
  @xml.escape_text(value)
  .replace_all(old="\"", new="&quot;")
  .replace_all(old="'", new="&apos;")
  .replace_all(old="\t", new="&#9;")
  .replace_all(old="\n", new="&#10;")
  .replace_all(old="\r", new="&#13;")
}

///|
fn Session::add_slide(
  self : Session,
  index : Int32,
  copy~ : Bool = false,
) -> Json raise @failure.Failure {
  guard self.slides.length() < 256 else {
    @failure.reject("limit-exceeded", "Slides exceed 256")
  }
  let root = self.main.root("presentation")
  let list = self.main.required(root.id, "sldIdLst", uri=presentation_uri)
  let nodes = self.main.all(list.id, "sldId", uri=presentation_uri)
  let links = self.relationships()
  let segments = self.main.part
    .split("/")
    .map(segment => segment.to_owned())
    .to_array()
  ignore(segments.pop())
  let directory = if segments.is_empty() {
    ""
  } else {
    segments.join("/") + "/"
  }
  let mut identity = self.slide_sequence
  let mut part = ""
  let mut link = ""
  while true {
    guard identity < 2147483647L else {
      @failure.reject("limit-exceeded", "Slide identity exhausted")
    }
    part = directory + "slides/slide\{identity}.xml"
    link = "odSlide\{identity}"
    if !self.opc.names.contains(part.to_lower()) &&
      !self.opc.names.contains(relationship_part(part).to_lower()) &&
      !self.slides.any(slide => slide.tree.part.to_lower() == part.to_lower()) &&
      !nodes.any(node => {
        source_identity(node.attribute("id").unwrap_or("")) ==
        identity.to_string()
      }) &&
      !links.iter().any(rel => rel.owner == self.main.part && rel.id == link) {
      break
    }
    identity += 1L
  }
  let parts = self.parts.copy()
  let media = self.media.copy()
  let created_parts : Map[String, @xml.Document] = Map([])
  let created_media : Map[String, Bytes] = Map([])
  let edits : Array[(String, @xml.Edit)] = []
  let mut extra_types = ""
  let mut object_sequence = self.object_sequence
  let current = self.slides[index]
  let layout = slide_layout(self.opc, current.tree.part, parts).unwrap()
  let relation_xml = "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"layout\" Type=\"\{relationship_uri}/slideLayout\" Target=\"/\{xml_attribute(layout)}\"/></Relationships>"
  let relation_path = relationship_part(part)
  let mut relations = @xml.Document::parse(
    @utf8.encode(relation_xml),
    relation_path,
    self.budget.xml_depth,
    self.budget.entry_bytes,
  )
  parts[relation_path] = relations
  let mut document = @xml.Document::parse(
    @utf8.encode(empty_slide()),
    part,
    self.budget.xml_depth,
    self.budget.entry_bytes,
  )
  if copy {
    let (copied, documents, workbooks, types, metadata, next) = self.copy_slide_parts(
      current, part, identity,
    )
    document = copied
    relations = documents[relation_path]
    for name, value in documents {
      parts[name] = value
      if name != relation_path {
        created_parts[name] = value
      }
    }
    for name, bytes in workbooks {
      media[name] = bytes
      created_media[name] = bytes
    }
    extra_types = types
    object_sequence = next
    for (name, value, edit) in metadata {
      parts[name] = value
      edits.push((name, edit))
    }
  }
  let (main_document, edit) = self.main.document.edit_source([
    {
      node: list.id,
      offset: nodes[index].end - list.start,
      length: 0,
      xml: "<od:sldId xmlns:od=\"\{presentation_uri}\" xmlns:r=\"\{relationship_uri}\" id=\"\{identity}\" r:id=\"\{link}\"/>",
    },
  ])
  edits.push((self.main.part, edit))
  let main = sync_slide_sections(
    self.main,
    Tree::new(self.main.part, main_document),
    edits,
    if copy {
      CopySlide
    } else {
      AddSlide
    },
    index,
  )
  let added = read_slide(
    self.opc,
    main,
    self.cache,
    Tree::new(part, document),
    index=index + 1,
    date_time=self.date_time,
    parts~,
  )
  let slides = self.slides.copy()
  slides.insert(index + 1, added)
  for
    (path, markup) in [
      (
        relationship_part(main.part),
        "<od:Relationship xmlns:od=\"http://schemas.openxmlformats.org/package/2006/relationships\" Id=\"\{link}\" Type=\"\{relationship_uri}/slide\" Target=\"slides/slide\{identity}.xml\"/>",
      ),
      (
        "[Content_Types].xml",
        "<od:Override xmlns:od=\"http://schemas.openxmlformats.org/package/2006/content-types\" PartName=\"/\{xml_attribute(part)}\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slide+xml\"/>" +
        extra_types,
      ),
    ] {
    let original = parts.get(path).unwrap_or_else(() => self.opc.xml(path))
    let (updated, edit) = original.edit_source([
      insertion(original.nodes()[0], markup),
    ])
    parts[path] = updated
    edits.push((path, edit))
  }
  self.commit_slides(
    main,
    slides,
    edits,
    {
      slide: part,
      object: "",
      objects: [],
      mode: "object",
      anchor: 0,
      focus: 0,
    },
    parts~,
    created=[(added, relations)],
    created_parts~,
    media~,
    created_media~,
  )
  self.slide_sequence = identity + 1L
  self.object_sequence = object_sequence
  self.query()
}
