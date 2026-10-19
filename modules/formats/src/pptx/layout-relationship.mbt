///|
fn Session::change_layout_relationship(
  self : Session,
  owner : String,
  layout : String,
  parts : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
) -> Unit raise @failure.Failure {
  let path = relationship_part(owner)
  let original = parts.get(path).unwrap_or_else(() => self.opc.xml(path))
  let links = original
    .nodes()
    .filter(node => {
      node.attribute("Type") == Some(relationship_uri + "/slideLayout")
    })
  guard links is [link] else {
    @failure.reject("malformed-pptx", "Invalid slide layout relationship")
  }
  let tree = Tree::new(path, original)
  let (document, edit) = original.edit_source([
    attribute_change(
      { tree, node: link, },
      "Target",
      xml_attribute("/" + layout),
    ),
  ])
  parts[path] = document
  edits.push((path, edit))
}
