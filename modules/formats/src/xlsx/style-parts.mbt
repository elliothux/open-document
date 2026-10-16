///|
fn Session::styles_part(
  self : Session,
  parts : Map[String, @xml.Document],
) -> String? raise @failure.Failure {
  let document = parts
    .get(workbook_relations(self.main))
    .unwrap_or_else(() => self.opc.xml(workbook_relations(self.main)))
  let root = document.nodes()[0]
  let links = document
    .nodes()
    .filter(node => {
      node.parent == root.id &&
      node.attribute("Type") == Some(relationship_uri + "styles")
    })
  guard links.length() <= 1 else {
    @failure.reject("malformed-xlsx", "Multiple style owners")
  }
  guard links.get(0) is Some(link) else { return None }
  guard link.attribute("TargetMode") != Some("External") else {
    @failure.reject("malformed-xlsx", "External cell styles")
  }
  Some(@opc.resolve_target(self.main, link.attribute("Target").unwrap_or("")))
}

///|
fn Session::styles_from_parts(
  self : Session,
  parts : Map[String, @xml.Document],
) -> Array[CellStyle] raise @failure.Failure {
  guard self.styles_part(parts) is Some(part) else { return [default_style()] }
  read_styles(
    parts.get(part).unwrap_or_else(() => self.opc.xml(part)),
    self.theme,
  )
}
