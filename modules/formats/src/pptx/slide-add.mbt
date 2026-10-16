///|
fn xml_attribute(value : String) -> String raise @failure.Failure {
  @xml.escape_text(value).replace_all(old="\"", new="&quot;")
}

///|
fn Session::add_slide(
  self : Session,
  index : Int,
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
  let current = self.slides[index]
  let layout = slide_layout(self.opc, current.tree.part, parts).unwrap()
  let relation_xml = "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"layout\" Type=\"\{relationship_uri}/slideLayout\" Target=\"/\{xml_attribute(layout)}\"/></Relationships>"
  let relation_path = relationship_part(part)
  let relations = @xml.Document::parse(
    @utf8.encode(relation_xml),
    relation_path,
    self.budget.xml_depth,
    self.budget.entry_bytes,
  )
  parts[relation_path] = relations
  let document = @xml.Document::parse(
    @utf8.encode(empty_slide()),
    part,
    self.budget.xml_depth,
    self.budget.entry_bytes,
  )
  let (main_document, edit) = self.main.document.edit_source([
    {
      node: list.id,
      offset: nodes[index].end - list.start,
      length: 0,
      xml: "<od:sldId xmlns:od=\"\{presentation_uri}\" xmlns:r=\"\{relationship_uri}\" id=\"\{identity}\" r:id=\"\{link}\"/>",
    },
  ])
  let main = Tree::new(self.main.part, main_document)
  let added = read_slide(
    self.opc,
    main,
    self.cache,
    Tree::new(part, document),
    parts~,
  )
  let slides = self.slides.copy()
  slides.insert(index + 1, added)
  let edits : Array[(String, @xml.Edit)] = [(main.part, edit)]
  for
    (path, markup) in [
      (
        relationship_part(main.part),
        "<od:Relationship xmlns:od=\"http://schemas.openxmlformats.org/package/2006/relationships\" Id=\"\{link}\" Type=\"\{relationship_uri}/slide\" Target=\"slides/slide\{identity}.xml\"/>",
      ),
      (
        "[Content_Types].xml",
        "<od:Override xmlns:od=\"http://schemas.openxmlformats.org/package/2006/content-types\" PartName=\"/\{xml_attribute(part)}\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slide+xml\"/>",
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
    { slide: part, object: "", mode: "object", anchor: 0, focus: 0, },
    parts~,
    created=Some((added, relations)),
  )
  self.slide_sequence = identity + 1L
  self.query()
}
