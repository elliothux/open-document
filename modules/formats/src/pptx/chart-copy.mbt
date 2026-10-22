///|
fn chart_frame_reference(tree : Tree, node : @xml.Node) -> Bool {
  if node.uri != chart_uri ||
    node.name != "chart" ||
    node.attributes.length() != 1 ||
    node.attribute("id", uri=relationship_uri) is None ||
    !tree.children.get(node.id).unwrap_or([]).is_empty() ||
    node.parent < 0 {
    return false
  }
  let parent = tree.nodes[node.parent]
  parent.uri == drawing_uri &&
  parent.name == "graphicData" &&
  parent.attribute("uri") == Some(chart_uri) &&
  tree.children.get(parent.id).unwrap_or([]).length() == 1
}

///|
fn Session::chart_workbook(
  self : Session,
  chart : DrawingChart,
) -> Bytes raise @failure.Failure {
  let bytes = self.media
    .get(chart.workbook)
    .unwrap_or_else(() => self.opc.read(chart.workbook))
  let actual = chart_data(
    chart.data.kind,
    chart.data.title,
    bytes,
    self.budget,
    hole_size=chart.data.hole_size,
    legend=Some(chart.data.legend),
  )
  guard actual == chart.data else {
    @failure.reject(
      "protected-content", "Chart cache and embedded workbook disagree",
    )
  }
  bytes
}

///|
fn Session::copy_chart_parts(
  self : Session,
  chart : DrawingChart,
  identity : String,
  documents : Map[String, @xml.Document],
  workbooks : Map[String, Bytes],
) -> (String, String) raise @failure.Failure {
  let links = self.relationships().filter(link => link.owner == chart.part)
  guard links is [link] &&
    !link.external &&
    link.kind == relationship_uri + "/package" &&
    link.target == chart.workbook else {
    @failure.reject(
      "protected-content", "Chart resource ownership requires copying support",
    )
  }
  let bytes = self.chart_workbook(chart)
  let source = self.part_document(chart.part)
  let relations = self.part_document(relationship_part(chart.part))
  let payload = documents
    .values()
    .fold(init=0L, (n, doc) => n + doc.source().length().to_int64() * 2) +
    workbooks.values().fold(init=0L, (n, book) => n + book.length().to_int64()) +
    (
      source.source().length().to_int64() +
      relations.source().length().to_int64()
    ) *
    2 +
    bytes.length().to_int64()
  guard payload <= 4194304L else {
    @failure.reject(
      "limit-exceeded", "Copied chart resources exceed history budget",
    )
  }
  let segments = self.main.part.split("/").map(s => s.to_owned()).to_array()
  ignore(segments.pop())
  let prefix = if segments.is_empty() { "" } else { segments.join("/") + "/" }
  let mut sequence = 0
  let mut part = ""
  let mut workbook = ""
  while true {
    part = prefix + "charts/odCopy\{identity}-\{sequence}.xml"
    workbook = prefix + "embeddings/odCopy\{identity}-\{sequence}.xlsx"
    if [part, relationship_part(part), workbook].all(name => {
        !self.opc.names.contains(name.to_lower()) &&
        !self.parts.contains(name) &&
        !self.media.contains(name) &&
        !documents.contains(name) &&
        !workbooks.contains(name)
      }) {
      break
    }
    sequence += 1
    guard sequence <= self.budget.entries else {
      @failure.reject("limit-exceeded", "Copied chart identities exhausted")
    }
  }
  let link = links[0]
  let node = relations
    .nodes()
    .iter()
    .find_first(n => n.attribute("Id") == Some(link.id))
    .unwrap()
  let (relations, _) = relations.edit_source([
    attribute_change(
      { tree: Tree::new(relationship_part(chart.part), relations), node, },
      "Target",
      xml_attribute("/" + workbook),
    ),
  ])
  documents[part] = @xml.Document::parse(
    source.bytes(),
    part,
    self.budget.xml_depth,
    self.budget.entry_bytes,
  )
  documents[relationship_part(part)] = @xml.Document::parse(
    relations.bytes(),
    relationship_part(part),
    self.budget.xml_depth,
    self.budget.entry_bytes,
  )
  workbooks[workbook] = bytes
  (
    part,
    "<Override xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\" PartName=\"/\{xml_attribute(part)}\" ContentType=\"application/vnd.openxmlformats-officedocument.drawingml.chart+xml\"/><Override xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\" PartName=\"/\{xml_attribute(workbook)}\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet\"/>",
  )
}
