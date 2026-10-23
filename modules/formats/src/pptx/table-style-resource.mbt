///|
fn Session::table_style_resource(
  self : Session,
  book : TableStyleBook,
  id : String,
  parts : Map[String, @xml.Document],
  created : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
) -> Unit raise @failure.Failure {
  let style = book.styles[id]
  let markup = style.tree.standalone_markup(style.tree.document, style.node.id)
  if book.part is Some(part) {
    let document = parts
      .get(part)
      .unwrap_or_else(() => self.part_document(part))
    if document
      .nodes()
      .any(node => {
        node.uri == drawing_uri &&
        node.name == "tblStyle" &&
        node.attribute("styleId").map(s => s.to_upper()) == Some(id)
      }) {
      return
    }
    let (next, edit) = document.edit_source([
      insertion(document.nodes()[0], markup),
    ])
    parts[part] = next
    if created.contains(part) {
      created[part] = next
    } else {
      edits.push((part, edit))
    }
    return
  }
  let segments = self.main.part.split("/").map(s => s.to_owned()).to_array()
  ignore(segments.pop())
  let directory = if segments.is_empty() {
    ""
  } else {
    segments.join("/") + "/"
  }
  let part = for sequence in 1..<=self.budget.entries {
    let path = directory + "odTableStyles\{sequence}.xml"
    if !self.opc.names.contains(path.to_lower()) && !parts.contains(path) {
      break path
    }
  } nobreak {
    @failure.reject("limit-exceeded", "Table style identities exhausted")
  }
  // A neutral default preserves tables that previously had no style resource.
  let neutral = "{00000000-0000-0000-0000-000000000000}"
  let document = @xml.Document::parse(
    @utf8.encode(
      "<a:tblStyleLst xmlns:a=\"\{drawing_uri}\" def=\"\{neutral}\"><a:tblStyle styleId=\"\{neutral}\" styleName=\"Document default\"><a:wholeTbl/></a:tblStyle>\{markup}</a:tblStyleLst>",
    ),
    part,
    self.budget.xml_depth,
    self.budget.entry_bytes,
  )
  parts[part] = document
  created[part] = document
  let links = self.relationships()
  let identity = for sequence in 1..<=self.budget.entries {
    let identity = "odTableStyles\{sequence}"
    if !links.any(link => link.owner == self.main.part && link.id == identity) {
      break identity
    }
  } nobreak {
    @failure.reject(
      "limit-exceeded", "Table style relationship identities exhausted",
    )
  }
  for
    (path, xml) in [
      (
        relationship_part(self.main.part),
        "<od:Relationship xmlns:od=\"http://schemas.openxmlformats.org/package/2006/relationships\" Id=\"\{identity}\" Type=\"\{relationship_uri}/tableStyles\" Target=\"/\{xml_attribute(part)}\"/>",
      ),
      (
        "[Content_Types].xml",
        "<od:Override xmlns:od=\"http://schemas.openxmlformats.org/package/2006/content-types\" PartName=\"/\{xml_attribute(part)}\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.tableStyles+xml\"/>",
      ),
    ] {
    let original = parts
      .get(path)
      .unwrap_or_else(() => self.part_document(path))
    let (next, edit) = original.edit_source([
      insertion(original.nodes()[0], xml),
    ])
    parts[path] = next
    edits.push((path, edit))
  }
}
