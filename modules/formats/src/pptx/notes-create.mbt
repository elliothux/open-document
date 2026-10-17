///|
fn Session::notes_shape(
  self : Session,
  tree : Tree?,
  text : String,
) -> String raise @failure.Failure {
  let reserved : Map[String, Bool] = Map([])
  if tree is Some(tree) {
    reserve_drawing_identities(tree.document, reserved)
  }
  let mut id = 2
  while reserved.contains(id.to_string()) {
    id += 1
    guard id <= 16384 else {
      @failure.reject("limit-exceeded", "Notes shape identity budget exceeded")
    }
  }
  let size = self.main.one(
    self.main.root("presentation").id,
    "notesSz",
    uri=presentation_uri,
  )
  let width = number(
    size.bind(n => n.attribute("cx")).unwrap_or("6858000"),
    1,
    182880000,
  )
  let height = number(
    size.bind(n => n.attribute("cy")).unwrap_or("9144000"),
    1,
    182880000,
  )
  let paragraphs = text
    .split("\n")
    .to_array()
    .map(line => "<a:p>" + generated_text(line.to_owned(), "a:", "") + "</a:p>")
    .join("")
  "<p:sp xmlns:p=\"\{presentation_uri}\" xmlns:a=\"\{drawing_uri}\"><p:nvSpPr><p:cNvPr id=\"\{id}\" name=\"Notes\"/><p:cNvSpPr><a:spLocks noGrp=\"1\"/></p:cNvSpPr><p:nvPr><p:ph type=\"body\" idx=\"1\"/></p:nvPr></p:nvSpPr><p:spPr><a:xfrm><a:off x=\"\{(width * 0.1).round().to_int()}\" y=\"\{(height * 0.55).round().to_int()}\"/><a:ext cx=\"\{(width * 0.8).round().to_int().max(1)}\" cy=\"\{(height * 0.4).round().to_int().max(1)}\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></p:spPr><p:txBody><a:bodyPr/><a:lstStyle/>\{paragraphs}</p:txBody></p:sp>"
}

///|
fn Session::create_notes(
  self : Session,
  slide : String,
  text : String,
  parts : Map[String, @xml.Document],
  created : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
) -> Unit raise @failure.Failure {
  let segments = self.main.part.split("/").map(s => s.to_owned()).to_array()
  ignore(segments.pop())
  let directory = if segments.is_empty() {
    ""
  } else {
    segments.join("/") + "/"
  }
  let mut sequence = 1
  let mut part = ""
  while true {
    part = directory + "notesSlides/odNotes\{sequence}.xml"
    if !self.opc.names.contains(part.to_lower()) &&
      !parts.contains(part) &&
      !self.opc.names.contains(relationship_part(part).to_lower()) &&
      !parts.contains(relationship_part(part)) {
      break
    }
    sequence += 1
    guard sequence <= self.budget.entries else {
      @failure.reject("limit-exceeded", "Notes part identity budget exceeded")
    }
  }
  let shape = self.notes_shape(None, text)
  let document = @xml.Document::parse(
    @utf8.encode(
      "<p:notes xmlns:p=\"\{presentation_uri}\" xmlns:a=\"\{drawing_uri}\"><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>\{shape}</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:notes>",
    ),
    part,
    self.budget.xml_depth,
    self.budget.entry_bytes,
  )
  parts[part] = document
  created[part] = document
  let links = self.relationships()
  let master = links
    .iter()
    .find_first(l => {
      l.owner == self.main.part &&
      l.kind == relationship_uri + "/notesMaster" &&
      !l.external
    })
  let master_link = master
    .map(l => {
      "<Relationship Id=\"master\" Type=\"\{relationship_uri}/notesMaster\" Target=\"/\{xml_attribute(l.target)}\"/>"
    })
    .unwrap_or("")
  let path = relationship_part(part)
  let relations = @xml.Document::parse(
    @utf8.encode(
      "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"slide\" Type=\"\{relationship_uri}/slide\" Target=\"/\{xml_attribute(slide)}\"/>\{master_link}</Relationships>",
    ),
    path,
    self.budget.xml_depth,
    self.budget.entry_bytes,
  )
  parts[path] = relations
  created[path] = relations
  let mut id = 1
  while links.any(l => l.owner == slide && l.id == "odNotes\{id}") {
    id += 1
  }
  for
    (path, markup) in [
      (
        relationship_part(slide),
        "<od:Relationship xmlns:od=\"http://schemas.openxmlformats.org/package/2006/relationships\" Id=\"odNotes\{id}\" Type=\"\{relationship_uri}/notesSlide\" Target=\"/\{xml_attribute(part)}\"/>",
      ),
      (
        "[Content_Types].xml",
        "<od:Override xmlns:od=\"http://schemas.openxmlformats.org/package/2006/content-types\" PartName=\"/\{xml_attribute(part)}\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.notesSlide+xml\"/>",
      ),
    ] {
    let original = self.part_document(path)
    let (document, edit) = original.edit_source([
      insertion(original.nodes()[0], markup),
    ])
    parts[path] = document
    edits.push((path, edit))
  }
}
