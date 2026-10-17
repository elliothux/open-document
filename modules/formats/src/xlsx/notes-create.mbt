///|
fn Session::create_note_part(
  self : Session,
  owner : String,
  kind : String,
  source : String,
  parts : Map[String, @xml.Document],
  created : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
) -> (String, String) raise @failure.Failure {
  let directory = self.main.split("/").map(s => s.to_owned()).to_array()
  ignore(directory.pop())
  let prefix = if directory.is_empty() { "" } else { directory.join("/") + "/" }
  let extension = if kind == "comments" { "xml" } else { "vml" }
  let folder = if kind == "comments" { "comments" } else { "drawings" }
  let part = for i in 1..<=self.budget.entries {
    let candidate = prefix + folder + "/odNotes\{i}.\{extension}"
    if !self.opc.names.contains(candidate.to_lower()) &&
      !parts.contains(candidate) &&
      !self.opc.names.contains(workbook_relations(candidate).to_lower()) &&
      !parts.contains(workbook_relations(candidate)) {
      break candidate
    }
  } nobreak {
    @failure.reject("limit-exceeded", "Cell note part identities exhausted")
  }
  let document = @xml.Document::parse(
    @utf8.encode(source),
    part,
    self.budget.xml_depth,
    self.budget.entry_bytes,
  )
  parts[part] = document
  created[part] = document
  let links = self.relationships()
  let path = workbook_relations(owner)
  let path = self.opc.names.get(path.to_lower()).unwrap_or(path)
  let existing = if parts.get(path) is Some(document) {
    Some(document)
  } else if self.opc.names.contains(path.to_lower()) {
    Some(self.part_xml(path))
  } else {
    None
  }
  let id = for i in 1..<=16384 {
    let id = "odNote\{i}"
    if !links.any(l => l.owner == owner && l.id == id) &&
      !existing
      .map(d => d.nodes().any(n => n.attribute("Id") == Some(id)))
      .unwrap_or(false) {
      break id
    }
  } nobreak {
    @failure.reject(
      "limit-exceeded", "Cell note relationship identities exhausted",
    )
  }
  let markup = "<od:Relationship xmlns:od=\"http://schemas.openxmlformats.org/package/2006/relationships\" Id=\"\{id}\" Type=\"\{relationship_uri}\{kind}\" Target=\"/\{escaped_attribute(part)}\"/>"
  if existing is Some(original) {
    let (document, edit) = original.edit_source([
      insertion(original.nodes()[0], markup),
    ])
    parts[path] = document
    edits.push((path, edit))
  } else {
    let document = @xml.Document::parse(
      @utf8.encode(
        "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\{markup}</Relationships>",
      ),
      path,
      self.budget.xml_depth,
      self.budget.entry_bytes,
    )
    parts[path] = document
    created[path] = document
  }
  let path = "[Content_Types].xml"
  let original = parts.get(path).unwrap_or_else(() => self.part_xml(path))
  let content_type = if kind == "comments" {
    "application/vnd.openxmlformats-officedocument.spreadsheetml.comments+xml"
  } else {
    "application/vnd.openxmlformats-officedocument.vmlDrawing"
  }
  let (document, edit) = original.edit_source([
    insertion(
      original.nodes()[0],
      "<od:Override xmlns:od=\"http://schemas.openxmlformats.org/package/2006/content-types\" PartName=\"/\{escaped_attribute(part)}\" ContentType=\"\{content_type}\"/>",
    ),
  ])
  parts[path] = document
  edits.push((path, edit))
  (part, id)
}

///|
fn note_source(
  address : Address,
  text : String,
  author : Int,
) -> String raise @failure.Failure {
  "<od:comment xmlns:od=\"\{spreadsheet_uri}\" ref=\"\{address.name()}\" authorId=\"\{author}\"><od:text><od:t xml:space=\"preserve\">\{encode_text(text)}</od:t></od:text></od:comment>"
}

///|
fn note_body(
  tree : Tree,
  note : CellNote,
  text : String,
) -> String raise @failure.Failure {
  let value = "<odNote:t xmlns:odNote=\"\{spreadsheet_uri}\" xml:space=\"preserve\">\{encode_text(text)}</odNote:t>"
  guard tree.all(note.body.id, "r").get(0) is Some(run) else { return value }
  let source = tree.document.source()
  let opening = if run.empty {
    source[run.start:run.opening_end - 2].to_owned() + ">"
  } else {
    source[run.start:run.opening_end].to_owned()
  }
  let style = tree
    .one(run.id, "rPr")
    .map(n => source[n.start:n.end].to_owned())
    .unwrap_or("")
  opening + style + value + "</\{run.qualified}>"
}
