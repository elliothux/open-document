///|
fn Session::chart_part_document(
  self : Session,
  path : String,
  parts : Map[String, @xml.Document],
) -> @xml.Document? raise @failure.Failure {
  if parts.get(path) is Some(document) {
    Some(document)
  } else if self.opc.names.contains(path.to_lower()) {
    Some(self.opc.xml(path))
  } else {
    None
  }
}

///|
fn Session::store_chart_xml(
  self : Session,
  path : String,
  markup : String,
  parts : Map[String, @xml.Document],
  created : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
) -> Unit raise @failure.Failure {
  let document = @xml.Document::parse(
    @utf8.encode(markup),
    path,
    self.budget.xml_depth,
    self.budget.entry_bytes,
  )
  if self.chart_part_document(path, parts) is Some(before) {
    let node = before.nodes()[0]
    let root = document.nodes()[0]
    let tree = Tree::new(path, document)
    let body = tree.children
      .get(root.id)
      .unwrap_or([])
      .map(child => tree.standalone_markup(document, child.id))
      .join("")
    let (document, edit) = before.edit_source([
      {
        node: node.id,
        offset: node.opening_end - node.start,
        length: node.closing_start - node.opening_end,
        xml: body,
      },
    ])
    parts[path] = document
    edits.push((path, edit))
  } else {
    parts[path] = document
    created[path] = document
  }
}

///|
fn Session::append_chart_xml(
  self : Session,
  path : String,
  markup : String,
  parts : Map[String, @xml.Document],
  created : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
) -> Unit raise @failure.Failure {
  let before = self.chart_part_document(path, parts)
  let document = before.unwrap_or_else(() => {
    @xml.Document::parse(
      b"<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"/>",
      path,
      self.budget.xml_depth,
      self.budget.entry_bytes,
    )
  })
  let (document, edit) = document.edit_source([
    insertion(document.nodes()[0], markup),
  ])
  parts[path] = document
  if before is None {
    created[path] = document
  } else {
    edits.push((path, edit))
  }
}

///|
fn Session::write_chart(
  self : Session,
  kind : String,
  title : String,
  source : String,
  placement : (Double, Double, Double, Double)?,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  guard source.length() <= 65536 else {
    @failure.reject("limit-exceeded", "Chart data exceeds 65536 characters")
  }
  let original = self.current()
  guard original.tree.document.nodes()[0].name == "sld" else {
    @failure.reject(
      "protected-content", "Create and edit charts in a slide view",
    )
  }
  let target = if placement is None {
    guard self.selection.mode == "object" && self.selection.objects is [id] else {
      @failure.reject("invalid-chart", "Select one chart to edit data")
    }
    let object = original.object(id)
    guard object.chart is Some(chart) &&
      object.read_only.is_empty() &&
      object.parent.is_empty() else {
      @failure.reject(
        "protected-content", "Chart data requires an editable local chart",
      )
    }
    guard self.slides.fold(init=0, (sum, slide) => {
        sum +
        slide.objects
        .filter(o => o.chart.map(c => c.part == chart.part).unwrap_or(false))
        .length()
      }) ==
      1 &&
      self
      .relationships()
      .filter(link => !link.external && link.target == chart.part)
      .length() ==
      1 else {
      @failure.reject(
        "protected-content", "Shared chart resources require independent copying before editing",
      )
    }
    for node in object.source.tree.document.nodes() {
      if node.start >= object.source.node.start &&
        node.end <= object.source.node.end &&
        node.name.has_suffix("Locks") &&
        (flag(node, "noDrilldown") || flag(node, "noSelect")) {
        @failure.reject("protected-content", "Chart data editing is locked")
      }
    }
    ignore(self.chart_workbook(chart))
    Some((object, chart))
  } else {
    None
  }
  let workbook = @xlsx.Session::import_delimited(
    @utf8.encode(source),
    "\t",
    self.budget,
    numbers=true,
  )
  defer workbook.close()
  let bytes = workbook.save()
  let data = chart_data(kind, title, bytes, self.budget)
  if data.kind != "pie" {
    ignore(data.axis())
  }
  if target is Some((_, chart)) && chart.data == data {
    return self.query()
  }
  let id = target
    .map(pair => pair.0.id.split("#").last().unwrap().to_owned())
    .unwrap_or_else(() => self.next_object_identity())
  let (x, y, width, height) = placement.unwrap_or_else(() => {
    let g = target.unwrap().0.geometry.unwrap()
    (g.x, g.y, g.width, g.height)
  })
  validate_object_box(x, y, width, height, false)
  let segments = self.main.part.split("/").map(v => v.to_owned()).collect()
  ignore(segments.pop())
  let directory = segments.join("/")
  let mut sequence = 1
  let links = self.relationships()
  let mut chart_part = ""
  let mut workbook_part = ""
  let mut link = ""
  while true {
    chart_part = target
      .map(pair => pair.1.part)
      .unwrap_or(
        directory + "/charts/chart" + id + "_" + sequence.to_string() + ".xml",
      )
    workbook_part = directory +
      "/embeddings/chart" +
      id +
      "_" +
      sequence.to_string() +
      ".xlsx"
    link = "odChart" + id + "_" + sequence.to_string()
    if !self.opc.names.contains(workbook_part.to_lower()) &&
      !self.media.contains(workbook_part) &&
      (
        target is Some(_) ||
        (
          !self.opc.names.contains(chart_part.to_lower()) &&
          !self.parts.contains(chart_part)
        )
      ) &&
      !links.any(rel => rel.owner == original.tree.part && rel.id == link) {
      break
    }
    sequence += 1
    guard sequence <= 16384 else {
      @failure.reject("limit-exceeded", "Chart identities exhausted")
    }
  }
  let parts = self.parts.copy()
  let media = self.media.copy()
  let created : Map[String, @xml.Document] = Map([])
  let edits : Array[(String, @xml.Edit)] = []
  media[workbook_part] = bytes
  let chart_rels = relationship_part(chart_part)
  let workbook_link = if target is Some(_) {
    let chart = parts
      .get(chart_part)
      .unwrap_or_else(() => self.opc.xml(chart_part))
    chart
    .nodes()
    .iter()
    .find_first(n => n.uri == chart_uri && n.name == "externalData")
    .unwrap()
    .attribute("id", uri=relationship_uri)
    .unwrap()
  } else {
    "workbook"
  }
  if target is Some(_) {
    let relations = self.chart_part_document(chart_rels, parts).unwrap()
    let node = relations
      .nodes()
      .iter()
      .find_first(n => n.attribute("Id") == Some(workbook_link))
      .unwrap()
    let (relations, edit) = relations.edit_source([
      attribute_change(
        { tree: Tree::new(chart_rels, relations), node, },
        "Target",
        "/" + workbook_part,
      ),
    ])
    parts[chart_rels] = relations
    edits.push((chart_rels, edit))
  } else {
    self.append_chart_xml(
      chart_rels,
      "<Relationship xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\" Id=\"workbook\" Type=\"\{relationship_uri}/package\" Target=\"/\{workbook_part}\"/>",
      parts,
      created,
      edits,
    )
    self.append_chart_xml(
      relationship_part(original.tree.part),
      "<Relationship xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\" Id=\"\{link}\" Type=\"\{relationship_uri}/chart\" Target=\"/\{chart_part}\"/>",
      parts,
      created,
      edits,
    )
  }
  self.store_chart_xml(
    chart_part,
    data.markup(workbook_link),
    parts,
    created,
    edits,
  )
  let chart_type = if target is None {
    "<Override xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\" PartName=\"/\{chart_part}\" ContentType=\"application/vnd.openxmlformats-officedocument.drawingml.chart+xml\"/>"
  } else {
    ""
  }
  self.append_chart_xml(
    "[Content_Types].xml",
    chart_type +
    "<Override xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\" PartName=\"/\{workbook_part}\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet\"/>",
    parts,
    created,
    edits,
  )
  let document = if target is None {
    let (document, edit) = original.tree.document.edit_source([
      object_insertion(
        original.tree,
        chart_frame(id, link, x, y, width, height),
      ),
    ])
    edits.push((original.tree.part, edit))
    document
  } else {
    original.tree.document
  }
  let slide = read_slide(
    self.opc,
    self.main,
    self.cache,
    Tree::new(original.tree.part, document),
    index=self.source_index(original.tree.part),
    date_time=self.date_time,
    parts~,
  )
  let identity = original.tree.part + "#" + id
  let chart = slide.object(identity).chart.unwrap_or_else(() => {
    @failure.reject("invalid-chart", slide.object(identity).diagnostic)
  })
  ignore(chart.paint(width, height, probe, profile))
  self.commit_page(
    slide,
    edits,
    {
      ..self.selection,
      object: identity,
      objects: [identity],
      mode: "object",
      anchor: 0,
      focus: 0,
    },
    parts~,
    media~,
    created_parts=created,
    created_media=Map([(workbook_part, bytes)]),
    probe~,
    profile~,
  )
  if target is None {
    self.object_sequence = number(id, 1, 4294967295).to_int64() + 1
  }
  self.query()
}
