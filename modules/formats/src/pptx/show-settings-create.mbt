///|
fn Session::create_show_properties(
  self : Session,
  value : ShowSettings,
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
  let links = self.relationships()
  let mut id = 1
  let mut part = ""
  for ;; {
    part = directory + "odPresProps\{id}.xml"
    if !self.opc.names.contains(part.to_lower()) &&
      !parts.contains(part) &&
      !links.any(link => {
        link.owner == self.main.part && link.id == "odPresProps\{id}"
      }) {
      break
    }
    id += 1
    guard id <= self.budget.entries else {
      @failure.reject(
        "limit-exceeded", "Show properties part identity budget exceeded",
      )
    }
  }
  let markup = "<p:presentationPr xmlns:p=\"\{presentation_uri}\">\{show_settings_markup(value)}</p:presentationPr>"
  let document = @xml.Document::parse(
    @utf8.encode(markup),
    part,
    self.budget.xml_depth,
    self.budget.entry_bytes,
  )
  parts[part] = document
  created[part] = document
  for
    (path, markup) in [
      (
        relationship_part(self.main.part),
        "<od:Relationship xmlns:od=\"http://schemas.openxmlformats.org/package/2006/relationships\" Id=\"odPresProps\{id}\" Type=\"\{relationship_uri}/presProps\" Target=\"/\{xml_attribute(part)}\"/>",
      ),
      (
        "[Content_Types].xml",
        "<od:Override xmlns:od=\"http://schemas.openxmlformats.org/package/2006/content-types\" PartName=\"/\{xml_attribute(part)}\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.presProps+xml\"/>",
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
