///|
fn Session::copy_sheet_charts(
  self : Session,
  source : Sheet,
  target : Sheet,
  number : Int,
  created : Map[String, @xml.Document],
  remapped : Map[String, String],
  types : StringBuilder,
) -> Unit raise @failure.Failure {
  guard self.picture_drawing(source) is Some((drawing, tree)) else { return }
  let links = self.relationships()
  let directory = self.main.split("/").map(p => p.to_owned()).to_array()
  ignore(directory.pop())
  let prefix = if directory.is_empty() { "" } else { directory.join("/") + "/" }
  let mut count = 0
  for link in links {
    if link.owner != drawing ||
      link.kind != relationship_uri + "chart" ||
      !tree.document
      .nodes()
      .any(node => {
        node.uri == chart_uri &&
        node.name == "chart" &&
        node.attribute(
          "id",
          uri=relationship_uri[:relationship_uri.length() - 1].to_owned(),
        ) ==
        Some(link.id)
      }) {
      continue
    }
    count += 1
    guard !link.external &&
      count <= 256 &&
      !links.any(child => child.owner == link.target) &&
      links
      .filter(other => {
        !other.external &&
        other.kind == relationship_uri + "chart" &&
        other.target == link.target
      })
      .length() ==
      1 else {
      @failure.reject(
        "protected-content", "Chart ownership or resources require independent copying support",
      )
    }
    let original = self.part_xml(link.target)
    ignore(@chart.read_worksheet(link.target, original))
    guard original.source().length() <= 2097152 else {
      @failure.reject("limit-exceeded", "Copied chart exceeds history budget")
    }
    let part = for i in 0..<=self.budget.entries {
      let part = prefix + "charts/odSheet\{number}-\{i}.xml"
      if !self.opc.names.contains(part.to_lower()) &&
        !self.parts.contains(part) &&
        !created.contains(part) &&
        !self.opc.names.contains(workbook_relations(part).to_lower()) &&
        !self.parts.contains(workbook_relations(part)) {
        break part
      }
    } nobreak {
      @failure.reject("limit-exceeded", "Copied chart identities exhausted")
    }
    let changes = sheet_reference_changes(
      original,
      source.name,
      Some(target.name),
      charts=true,
    )
    let bytes = if changes.is_empty() {
      original.bytes()
    } else {
      original.edit_source(changes).0.bytes()
    }
    created[part] = @xml.Document::parse(
      bytes,
      part,
      self.budget.xml_depth,
      self.budget.entry_bytes,
    )
    remapped[link.target] = part
    if self.copy_sheet_relations(link.target, part, remapped) is Some(document) {
      created[workbook_relations(part)] = document
    }
    types.write_string(
      "<od:Override xmlns:od=\"http://schemas.openxmlformats.org/package/2006/content-types\" PartName=\"/\{escaped_attribute(part)}\" ContentType=\"application/vnd.openxmlformats-officedocument.drawingml.chart+xml\"/>",
    )
  }
}
