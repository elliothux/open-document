///|
fn Session::clipboard_chart(
  self : Session,
  object : Object,
  resources : Map[String, Json],
) -> @xml.SourceChange raise @failure.Failure {
  let chart = object.chart.unwrap()
  let links = self.relationships().filter(link => link.owner == chart.part)
  guard links is [link] &&
    !link.external &&
    link.kind == relationship_uri + "/package" &&
    link.target == chart.workbook else {
    @failure.reject(
      "protected-content", "Chart resource ownership requires clipboard support",
    )
  }
  ignore(self.chart_workbook(chart))
  let document = self.part_document(chart.part)
  let xml = document.source()
  guard !xml.contains("<!--") && !xml[document.nodes()[0].start:].contains("<?") else {
    @failure.reject(
      "protected-content", "Annotated charts require portable copying support",
    )
  }
  let key = "chart\n" + chart.part
  let id = if resources.get(key) is Some({ "id": String(id), .. }) {
    id
  } else {
    guard resources.length() < 256 else {
      @failure.reject(
        "limit-exceeded", "Object clipboard exceeds 256 resources",
      )
    }
    let id = "odClip" + resources.length().to_string()
    resources[key] = {
      "id": id,
      "kind": "chart",
      "value": @chart.markup(chart.data, "workbook"),
    }
    id
  }
  let reference = object.source
    .child("graphic")
    .unwrap()
    .child("graphicData")
    .unwrap()
    .child("chart", uri=chart_uri)
    .unwrap()
  let attr = reference.node.attributes[0]
  {
    node: reference.node.id,
    offset: attr.start - reference.node.start,
    length: attr.end - attr.start,
    xml: id,
  }
}

///|
fn Session::attach_clipboard_chart(
  self : Session,
  data : @layout.ChartData,
  id : String,
  parts : Map[String, @xml.Document],
  media : Map[String, Bytes],
  created : Map[String, @xml.Document],
  created_media : Map[String, Bytes],
  edits : Array[(String, @xml.Edit)],
  reserved : Set[String],
) -> String raise @failure.Failure {
  let segments = self.main.part.split("/").map(s => s.to_owned()).to_array()
  ignore(segments.pop())
  let prefix = if segments.is_empty() { "" } else { segments.join("/") + "/" }
  let (chart, workbook, link) = for sequence in 0..<=self.budget.entries {
    let chart = prefix + "charts/odClip\{id}-\{sequence}.xml"
    let workbook = prefix + "embeddings/odClip\{id}-\{sequence}.xlsx"
    let link = "odClipboardChart\{id}_\{sequence}"
    if !reserved.contains(link) &&
      [chart, relationship_part(chart), workbook].all(path => {
        !self.opc.names.contains(path.to_lower()) &&
        !parts.contains(path) &&
        !media.contains(path)
      }) {
      break (chart, workbook, link)
    }
  } nobreak {
    @failure.reject("limit-exceeded", "Chart clipboard identities exhausted")
  }
  let bytes = @xlsx.chart_workbook(data, self.budget)
  media[workbook] = bytes
  created_media[workbook] = bytes
  self.store_chart_xml(
    chart,
    @chart.markup(data, "workbook"),
    parts,
    created,
    edits,
  )
  self.append_chart_xml(
    relationship_part(chart),
    "<Relationship xmlns='http://schemas.openxmlformats.org/package/2006/relationships' Id='workbook' Type='\{relationship_uri}/package' Target='/\{xml_attribute(workbook)}'/>",
    parts,
    created,
    edits,
  )
  self.append_chart_xml(
    relationship_part(self.current().tree.part),
    "<Relationship xmlns='http://schemas.openxmlformats.org/package/2006/relationships' Id='\{link}' Type='\{relationship_uri}/chart' Target='/\{xml_attribute(chart)}'/>",
    parts,
    created,
    edits,
  )
  self.append_chart_xml(
    "[Content_Types].xml",
    "<Override xmlns='http://schemas.openxmlformats.org/package/2006/content-types' PartName='/\{xml_attribute(chart)}' ContentType='application/vnd.openxmlformats-officedocument.drawingml.chart+xml'/><Override xmlns='http://schemas.openxmlformats.org/package/2006/content-types' PartName='/\{xml_attribute(workbook)}' ContentType='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'/>",
    parts,
    created,
    edits,
  )
  reserved.add(link)
  link
}
