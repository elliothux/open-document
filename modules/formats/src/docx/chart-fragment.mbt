///|
fn WordTree::check_fragment_chart(
  self : WordTree,
  drawing : Int,
  portable~ : Bool = false,
) -> Int raise @failure.Failure {
  let root = self.nodes[drawing]
  guard root.uri == word_uri &&
    root.name == "drawing" &&
    root.attributes.is_empty() &&
    self.nodes[root.parent].uri == word_uri &&
    self.nodes[root.parent].name == "r" else {
    @failure.reject(
      "protected-content", "Rich charts require ordinary drawings",
    )
  }
  let (frame, data) = self.drawing_data(drawing)
  guard ["inline", "anchor"].contains(frame.name) &&
    data.attribute("uri") == Some(chart_uri) &&
    self.children[data.id] is [chart] else {
    @failure.reject("protected-content", "Rich charts require one inline chart")
  }
  let rel_uri = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
  guard !self.source[self.nodes[chart].start:self.nodes[chart].end].contains(
      "<!--",
    ) &&
    !self.source[self.nodes[chart].start:self.nodes[chart].end].contains("<?") else {
    @failure.reject(
      "protected-content", "Opaque chart reference requires copying support",
    )
  }
  for id in self.descendants(drawing) {
    let node = self.nodes[id]
    let attributes = match node.name {
      "drawing" | "graphic" | "cNvGraphicFramePr" => []
      "inline" => ["distT", "distB", "distL", "distR"]
      "anchor" =>
        [
          "distT", "distB", "distL", "distR", "simplePos", "relativeHeight", "behindDoc",
          "locked", "layoutInCell", "allowOverlap",
        ]
      "simplePos" => ["x", "y"]
      "positionH" | "positionV" => ["relativeFrom"]
      "posOffset" | "align" | "wrapNone" => []
      "wrapTopAndBottom" => ["distT", "distB"]
      "wrapSquare" => ["distT", "distB", "distL", "distR", "wrapText"]
      "extent" => ["cx", "cy"]
      "effectExtent" => ["l", "t", "r", "b"]
      "docPr" => ["id", "name", "descr", "title", "hidden"]
      "graphicData" => ["uri"]
      "graphicFrameLocks" =>
        [
          "noGrp", "noSelect", "noResize", "noMove", "noChangeAspect", "noTextEdit",
          "noDelete", "noDrilldown", "noCopy", "noChangeWrap",
        ]
      "chart" => []
      _ => @failure.reject("protected-content", "Unknown rich chart metadata")
    }
    if node.name == "docPr" {
      let identity = @string.parse_int64(node.attribute("id").unwrap_or("")[:]) catch {
        _ =>
          @failure.reject("protected-content", "Invalid copied chart identity")
      }
      guard identity >= 0 && identity <= 4294967295L else {
        @failure.reject(
          "protected-content", "Copied chart identity exceeds native range",
        )
      }
    }
    let uri = match node.name {
      "drawing" => word_uri
      "inline"
      | "anchor"
      | "simplePos"
      | "positionH"
      | "positionV"
      | "posOffset"
      | "align"
      | "wrapNone"
      | "wrapTopAndBottom"
      | "wrapSquare"
      | "extent"
      | "effectExtent"
      | "docPr"
      | "cNvGraphicFramePr" => picture_inline_uri
      "chart" => chart_uri
      _ => picture_drawing_uri
    }
    guard node.uri == uri &&
      (
        node.text.trim().is_empty() ||
        ["posOffset", "align"].contains(node.name)
      ) &&
      node.attributes.all(attribute => {
        (attribute.uri.is_empty() && attributes.contains(attribute.name)) ||
        (
          node.id == frame.id &&
          frame.name == "anchor" &&
          attribute.uri == drawing_2010_uri &&
          ["anchorId", "editId"].contains(attribute.name) &&
          attribute.value.length() == 8 &&
          attribute.value.iter().all(c => c.is_ascii_hexdigit())
        ) ||
        (id == chart && attribute.uri == rel_uri && attribute.name == "id") ||
        (
          portable &&
          id == chart &&
          attribute.uri == table_fragment_uri &&
          ["chart", "relations", "workbook"].contains(attribute.name)
        )
      }) &&
      !self.shape_locked(drawing, "noCopy") else {
      @failure.reject(
        "protected-content", "Rich chart metadata or copying is protected",
      )
    }
  }
  guard self.nodes[chart].uri == chart_uri &&
    self.nodes[chart].name == "chart" &&
    self.children[chart].is_empty() &&
    self.nodes[chart].attribute("id", uri=rel_uri) is Some(link) &&
    !link.is_empty() &&
    self
    .descendants(drawing)
    .filter(id => self.nodes[id].name == "docPr")
    .length() ==
    1 else {
    @failure.reject(
      "protected-content", "Rich chart requires unique native identities",
    )
  }
  ignore(self.drawing_geometry(drawing))
  chart
}

///|
fn chart_fragment_relationship(
  document : @xml.Document,
) -> @xml.Node raise @failure.Failure {
  let nodes = document.nodes()
  let uri = "http://schemas.openxmlformats.org/package/2006/relationships"
  guard nodes is [root, link] &&
    root.uri == uri &&
    root.name == "Relationships" &&
    root.attributes.is_empty() &&
    link.parent == root.id &&
    link.uri == uri &&
    link.name == "Relationship" &&
    link.text.trim().is_empty() &&
    root.text.trim().is_empty() &&
    link.attributes.all(attribute => {
      attribute.uri.is_empty() &&
      ["Id", "Type", "Target", "TargetMode"].contains(attribute.name)
    }) &&
    link.attribute("Id") is Some(id) &&
    !id.is_empty() &&
    link.attribute("Target") is Some(_) &&
    link.attribute("Type") ==
    Some(
      "http://schemas.openxmlformats.org/officeDocument/2006/relationships/package",
    ) &&
    [None, Some("Internal")].contains(link.attribute("TargetMode")) else {
    @failure.reject(
      "protected-content", "Rich chart requires one internal embedded workbook relationship",
    )
  }
  link
}

///|
fn Session::fragment_chart(
  self : Session,
  tree : WordTree,
  drawing : Int,
  limit : Int,
) -> String raise @failure.Failure {
  let reference = tree.check_fragment_chart(drawing)
  let (_, chart) = self.editable_chart(tree, drawing, operation=ChartCopy)
  let bytes = self.media
    .get(chart.workbook)
    .unwrap_or_else(() => self.opc.read(chart.workbook))
  let segments = chart.part.split("/").to_array()
  let relations = segments[:segments.length() - 1]
    .map(segment => segment.to_owned())
    .join("/") +
    "/_rels/" +
    segments.last().unwrap().to_owned() +
    ".rels"
  let relations = self.part_xml(relations)
  ignore(chart_fragment_relationship(relations))
  let document = self.part_xml(chart.part)
  guard (
      document.bytes().length().to_int64() +
      relations.bytes().length().to_int64() +
      bytes.length().to_int64()
    ) *
    4 /
    3 +
    (tree.nodes[drawing].end - tree.nodes[drawing].start).to_int64() +
    1024 <=
    limit.to_int64() else {
    @failure.reject("limit-exceeded", "Rich chart exceeds clipboard budget")
  }
  let node = tree.nodes[reference]
  let (document, _) = self
    .document()
    .edit_source([
      {
        node: reference,
        offset: node.opening_end - node.start - (if node.empty { 2 } else { 1 }),
        length: 0,
        xml: " xmlns:odClip=\"\{table_fragment_uri}\" odClip:chart=\"\{@base64.encode(document.bytes())}\" odClip:relations=\"\{@base64.encode(relations.bytes())}\" odClip:workbook=\"\{@base64.encode(bytes)}\"",
      },
    ])
  let markup = WordTree::new(document).standalone_markup(document, drawing)
  guard markup.length() <= limit else {
    @failure.reject(
      "limit-exceeded", "Rich chart namespaces exceed clipboard budget",
    )
  }
  markup
}

///|
fn Session::import_fragment_chart(
  self : Session,
  tree : WordTree,
  drawing : Int,
  identity : String,
  parts : Map[String, @xml.Document],
  edits : Map[String, Array[@xml.Edit]],
  created : Map[String, @xml.Document],
  media : Map[String, Bytes],
  added : Map[String, Bytes],
) -> (String, Int) raise @failure.Failure {
  let reference = tree.check_fragment_chart(drawing, portable=true)
  let node = tree.nodes[reference]
  let payload = ["chart", "relations", "workbook"].map(name => {
    guard node.attribute(name, uri=table_fragment_uri) is Some(encoded) &&
      encoded.length() <= 2097152 else {
      @failure.reject(
        "protected-content", "Rich chart requires bounded portable resources",
      )
    }
    @base64.decode(encoded) catch {
      _ =>
        @failure.reject("invalid-chart", "Invalid copied chart resource bytes")
    }
  })
  let count = payload.fold(init=0, (count, bytes) => count + bytes.length())
  guard count <= 2097152 else {
    @failure.reject("limit-exceeded", "Rich chart resources exceed budget")
  }
  let segments = self.main.split("/").to_array()
  let directory = segments[:segments.length() - 1]
    .map(segment => segment.to_owned())
    .join("/")
  let prefix = if directory.is_empty() { "" } else { directory + "/" }
  let view = { ..self, parts, media, }
  let links = view.relationships()
  let (chart, workbook, relations, link) = for sequence = 1
                                               sequence <= 16384
                                               sequence = sequence + 1 {
    let chart = prefix + "charts/odPaste\{identity}_\{sequence}.xml"
    let workbook = prefix + "embeddings/odPaste\{identity}_\{sequence}.xlsx"
    let relations = prefix +
      "charts/_rels/odPaste\{identity}_\{sequence}.xml.rels"
    let link = "odChartPaste\{identity}_\{sequence}"
    if [chart, workbook, relations].all(path => {
        !self.opc.names.contains(path.to_lower()) &&
        !parts.contains(path) &&
        !media.contains(path)
      }) &&
      !links.any(relationship => {
        relationship.owner == self.main && relationship.id == link
      }) {
      break (chart, workbook, relations, link)
    }
  } nobreak {
    @failure.reject("limit-exceeded", "Rich chart identities exhausted")
  }
  fn parse(
    bytes : Bytes,
    path : String,
  ) -> @xml.Document raise @failure.Failure {
    @xml.Document::parse(
      bytes,
      path,
      self.opc.budget.xml_depth,
      self.opc.budget.entry_bytes,
    )
  }
  let document = parse(payload[0], chart)
  let relationships = parse(payload[1], relations)
  let relationship = chart_fragment_relationship(relationships)
  let attribute = relationship.attributes
    .iter()
    .find_first(attribute => attribute.name == "Target")
    .unwrap()
  let relationships = relationships.edit_source([
      {
        node: relationship.id,
        offset: attribute.start - relationship.start,
        length: attribute.end - attribute.start,
        xml: "/" + property_attribute(workbook),
      },
    ]).0
  parts[chart] = document
  parts[relations] = relationships
  created[chart] = document
  created[relations] = relationships
  media[workbook] = payload[2]
  added[workbook] = payload[2]
  let resource = @chart.read(self.opc, chart, parts)
  ignore({ ..self, parts, media, }.chart_workbook(resource))
  fn append(path : String, markup : String) -> Unit raise @failure.Failure {
    let path = self.opc.names.get(path.to_lower()).unwrap_or(path)
    if self.opc.names.contains(path.to_lower()) || parts.contains(path) {
      let before = parts.get(path).unwrap_or_else(() => self.part_xml(path))
      let (after, edit) = append_part_xml(before, markup)
      parts[path] = after
      if created.contains(path) {
        created[path] = after
      } else {
        edits.get_or_init(path, () => []).push(edit)
      }
    } else {
      let document = parse(
        @utf8.encode(
          "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\{markup}</Relationships>",
        ),
        path,
      )
      parts[path] = document
      created[path] = document
    }
  }
  append(
    prefix + "_rels/" + segments.last().unwrap().to_owned() + ".rels",
    "<Relationship xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\" Id=\"\{link}\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart\" Target=\"/\{property_attribute(chart)}\"/>",
  )
  append(
    self.opc.names["[content_types].xml"],
    "<Override xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\" PartName=\"/\{property_attribute(chart)}\" ContentType=\"application/vnd.openxmlformats-officedocument.drawingml.chart+xml\"/><Override xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\" PartName=\"/\{property_attribute(workbook)}\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet\"/>",
  )
  (
    "<c:chart xmlns:c=\"\{chart_uri}\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" r:id=\"\{link}\"/>",
    count,
  )
}
