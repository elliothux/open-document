///|
fn Session::new_word_part(
  self : Session,
  kind : String,
  parts : Map[String, @xml.Document],
  edits : Map[String, Array[@xml.Edit]],
  created : Map[String, @xml.Document],
) -> String raise @failure.Failure {
  let segments = self.main.split("/").to_array()
  let leaf = segments.last().unwrap().to_owned()
  let directory = segments[:segments.length() - 1]
    .map(v => v.to_owned())
    .join("/")
  let prefix = if directory.is_empty() { "" } else { directory + "/" }
  let name = for i = 0; i <= 65536; i = i + 1 {
    let name = prefix + (if i == 0 { "\{kind}.xml" } else { "\{kind}\{i}.xml" })
    if !self.opc.names.contains(name.to_lower()) && !parts.contains(name) {
      break name
    }
  } nobreak {
    @failure.reject("limit-exceeded", "No free Word part name")
  }
  let rels = prefix + "_rels/" + leaf + ".rels"
  let rels = self.opc.names.get(rels.to_lower()).unwrap_or(rels)
  let types = self.opc.names["[content_types].xml"]
  let type_uri = "http://schemas.openxmlformats.org/package/2006/content-types"
  let rel_uri = "http://schemas.openxmlformats.org/package/2006/relationships"
  let relationship_type = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/\{kind}"
  let ids = self
    .relationships()
    .iter()
    .filter(rel => rel.owner == self.main)
    .map(rel => rel.id)
    .to_array()
  let id = for i = 1; i <= 65536; i = i + 1 {
    let id = "odRel\{i}"
    if !ids.contains(id) {
      break id
    }
  } nobreak {
    @failure.reject("limit-exceeded", "No free Word relationship id")
  }
  let markup = "<od:Relationship xmlns:od=\"\{rel_uri}\" Id=\"\{id}\" Type=\"\{relationship_type}\" Target=\"" +
    property_attribute(name[prefix.length():].to_owned()) +
    "\"/>"
  if self.opc.names.contains(rels.to_lower()) || parts.contains(rels) {
    let (candidate, edit) = append_part_xml(self.part_xml(rels), markup)
    parts[rels] = candidate
    if created.contains(rels) {
      created[rels] = candidate
    } else {
      edits.get_or_init(rels, () => []).push(edit)
    }
  } else {
    let document = @xml.Document::parse(
      @utf8.encode(
        "<Relationships xmlns=\"\{rel_uri}\">\{markup}</Relationships>",
      ),
      rels,
      self.opc.budget.xml_depth,
      self.opc.budget.entry_bytes,
    )
    parts[rels] = document
    created[rels] = document
  }
  let (candidate, edit) = append_part_xml(
    self.part_xml(types),
    "<od:Override xmlns:od=\"\{type_uri}\" PartName=\"/" +
    property_attribute(name) +
    "\" ContentType=\"application/vnd.openxmlformats-officedocument." +
    (if kind == "theme" { "theme" } else { "wordprocessingml." + kind }) +
    "+xml\"/>",
  )
  parts[types] = candidate
  edits.get_or_init(types, () => []).push(edit)
  let document = @xml.Document::parse(
    @utf8.encode(
      if kind == "theme" {
        blank_word_theme()
      } else {
        "<w:\{kind} xmlns:w=\"\{word_uri}\"/>"
      },
    ),
    name,
    self.opc.budget.xml_depth,
    self.opc.budget.entry_bytes,
  )
  parts[name] = document
  created[name] = document
  name
}
