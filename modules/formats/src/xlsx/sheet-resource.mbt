///|
fn Session::create_sheet_resource(
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
  let extension = if kind == "vmlDrawing" { "vml" } else { "xml" }
  let folder = if kind == "pivotTable" {
    "pivotTables"
  } else if kind == "pivotCacheDefinition" || kind == "pivotCacheRecords" {
    "pivotCache"
  } else if kind == "chart" {
    "charts"
  } else if kind == "table" {
    "tables"
  } else if kind == "comments" {
    "comments"
  } else if kind == "slicer" {
    "slicers"
  } else if kind == "slicerCache" {
    "slicerCaches"
  } else if kind == "Timeline" {
    "timelines"
  } else if kind == "TimelineCache" {
    "timelineCaches"
  } else {
    "drawings"
  }
  let stem = if kind.has_prefix("pivot") ||
    kind.has_prefix("slicer") ||
    kind.has_prefix("Timeline") {
    "od" + kind
  } else if kind == "chart" {
    "odChart"
  } else if kind == "table" {
    "odTable"
  } else if kind == "drawing" {
    "odDrawing"
  } else {
    "odNotes"
  }
  let part = for i in 1..<=self.budget.entries {
    let candidate = prefix + folder + "/\{stem}\{i}.\{extension}"
    if !self.opc.names.contains(candidate.to_lower()) &&
      !parts.contains(candidate) &&
      !self.opc.names.contains(workbook_relations(candidate).to_lower()) &&
      !parts.contains(workbook_relations(candidate)) {
      break candidate
    }
  } nobreak {
    @failure.reject(
      "limit-exceeded", "Worksheet resource part identities exhausted",
    )
  }
  let document = @xml.Document::parse(
    @utf8.encode(source),
    part,
    self.budget.xml_depth,
    self.budget.entry_bytes,
  )
  parts[part] = document
  created[part] = document
  let content_type = if kind.has_prefix("slicer") || kind.has_prefix("Timeline") {
    "application/vnd.ms-excel.\{kind}+xml"
  } else if kind.has_prefix("pivot") {
    "application/vnd.openxmlformats-officedocument.spreadsheetml.\{kind}+xml"
  } else if kind == "chart" {
    "application/vnd.openxmlformats-officedocument.drawingml.chart+xml"
  } else if kind == "table" {
    "application/vnd.openxmlformats-officedocument.spreadsheetml.table+xml"
  } else if kind == "comments" {
    "application/vnd.openxmlformats-officedocument.spreadsheetml.comments+xml"
  } else if kind == "drawing" {
    "application/vnd.openxmlformats-officedocument.drawing+xml"
  } else {
    "application/vnd.openxmlformats-officedocument.vmlDrawing"
  }
  let id = self.attach_sheet_resource(
    owner, part, kind, content_type, parts, created, edits,
  )
  (part, id)
}

///|
fn Session::attach_sheet_resource(
  self : Session,
  owner : String,
  part : String,
  kind : String,
  content_type : String,
  parts : Map[String, @xml.Document],
  created : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
) -> String raise @failure.Failure {
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
    let id = (if kind.has_prefix("pivot") ||
        kind.has_prefix("slicer") ||
        kind.has_prefix("Timeline") {
        "od" + kind
      } else if kind == "table" {
        "odTable"
      } else {
        "odNote"
      }) +
      i.to_string()
    if !links.any(l => l.owner == owner && l.id == id) &&
      !existing
      .map(d => d.nodes().any(n => n.attribute("Id") == Some(id)))
      .unwrap_or(false) {
      break id
    }
  } nobreak {
    @failure.reject(
      "limit-exceeded", "Worksheet resource relationship identities exhausted",
    )
  }
  let uri = if kind.has_prefix("Timeline") {
    timeline_relationship_uri
  } else if kind.has_prefix("slicer") {
    slicer_relationship_uri
  } else {
    relationship_uri
  }
  let markup = "<od:Relationship xmlns:od=\"http://schemas.openxmlformats.org/package/2006/relationships\" Id=\"\{id}\" Type=\"\{uri}\{kind}\" Target=\"/\{escaped_attribute(part)}\"/>"
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
  if original
    .nodes()
    .iter()
    .find_first(node => {
      node.name == "Override" &&
      node
      .attribute("PartName")
      .map(name => name.to_lower() == "/" + part.to_lower())
      .unwrap_or(false)
    })
    is Some(node) {
    guard node.attribute("ContentType") == Some(content_type) else {
      @failure.reject(
        "protected-content", "Worksheet resource content type differs",
      )
    }
    return id
  }
  let (document, edit) = original.edit_source([
    insertion(
      original.nodes()[0],
      "<od:Override xmlns:od=\"http://schemas.openxmlformats.org/package/2006/content-types\" PartName=\"/\{escaped_attribute(part)}\" ContentType=\"\{content_type}\"/>",
    ),
  ])
  parts[path] = document
  edits.push((path, edit))
  id
}
