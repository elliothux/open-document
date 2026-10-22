///|
pub fn Session::edit_chart(
  self : Session,
  revision : Int,
  action : String,
  id : Int,
  kind : String,
  title : String,
  source : String,
  width : Double,
  height : Double,
  probe~ : @layout.TextProbe,
  profile~ : Map[String, String],
  images~ : @layout.Images,
  hole_size~ : Int? = None,
  legend~ : String? = None,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  guard ["insert", "update", "delete", "resize"].contains(action) else {
    @failure.reject("invalid-operation", "Unknown chart action")
  }
  if action == "resize" {
    let prepared = self.prepare_chart_resize(id, width, height)
    if prepared is Some(prepared) {
      self.check_picture_layout(
        prepared.document,
        Some(probe),
        profile,
        Some(images),
      )
      self.commit_edit(prepared.edit, prepared.document)
    }
    return self.edit_result(
      prepared.map(value => value.edit.paragraphs).unwrap_or([]),
    )
  }
  let document = self.document()
  let tree = WordTree::new(document)
  let target = if action == "insert" {
    None
  } else {
    Some(
      self.editable_chart(
        tree,
        id,
        operation=if action == "delete" { ChartDelete } else { ChartContent },
      ),
    )
  }
  if action == "delete" {
    tree.check_picture_references(id)
    return self.delete_drawing(document, tree, id, target.unwrap().0)
  }
  guard source.length() <= 65536 &&
    width >= 180 &&
    width <= 14400 &&
    height >= 150 &&
    height <= 14400 else {
    @failure.reject("invalid-chart", "Invalid chart data or frame dimensions")
  }
  let width = (width * 12700).round() / 12700
  let height = (height * 12700).round() / 12700
  let workbook = @xlsx.Session::import_delimited(
    @utf8.encode(source),
    "\t",
    self.opc.budget,
    numbers=true,
  )
  defer workbook.close()
  let bytes = workbook.save()
  let data = @xlsx.chart_data(
    kind,
    title,
    bytes,
    self.opc.budget,
    hole_size~,
    legend~,
  )
  let geometry = target.map(_ => tree.drawing_geometry(id))
  if target is Some((_, chart)) &&
    chart.data == data &&
    geometry is Some((before_width, before_height, _)) &&
    width == before_width &&
    height == before_height {
    return self.edit_result([])
  }
  let identity = if action == "insert" {
    self.next_drawing_identity()
  } else {
    id
  }
  let segments = self.main.split("/").to_array()
  let directory = segments[:segments.length() - 1]
    .map(value => value.to_owned())
    .join("/")
  let prefix = if directory.is_empty() { "" } else { directory + "/" }
  let reused = target.bind(pair => {
    let before = pair.1.data
    if before.label == data.label &&
      before.categories == data.categories &&
      before.series == data.series {
      Some(pair.1.workbook)
    } else {
      None
    }
  })
  let links = self.relationships()
  let (chart_part, workbook_part, link) = for sequence = 1
                                              sequence <= 16384
                                              sequence = sequence + 1 {
    let chart_part = target
      .map(pair => pair.1.part)
      .unwrap_or(prefix + "charts/chart\{identity}_\{sequence}.xml")
    let workbook_part = reused.unwrap_or(
      prefix + "embeddings/chart\{identity}_\{sequence}.xlsx",
    )
    let link = "odChart\{identity}_\{sequence}"
    if (
        target is Some(_) ||
        (
          !self.opc.names.contains(chart_part.to_lower()) &&
          !self.parts.contains(chart_part)
        )
      ) &&
      (
        reused is Some(_) ||
        (
          !self.opc.names.contains(workbook_part.to_lower()) &&
          !self.media.contains(workbook_part)
        )
      ) &&
      (
        target is Some(_) ||
        !links.iter().any(rel => rel.owner == self.main && rel.id == link)
      ) {
      break (chart_part, workbook_part, link)
    }
  } nobreak {
    @failure.reject("limit-exceeded", "Chart identities exhausted")
  }
  let prepared = if action == "insert" {
    self.prepare_drawing_insertion(chart_markup(identity, link, width, height))
  } else {
    self
    .prepare_chart_resize(id, width, height)
    .unwrap_or({
      document,
      typing_text: None,
      join_group: false,
      edit: {
        xml: [],
        parts: Map([]),
        created: Map([]),
        created_media: Map([]),
        before: self.selection,
        after: self.selection,
        paragraphs: [target.unwrap().0],
        bytes: 0,
      },
    })
  }
  let parts = self.parts.copy()
  let media = self.media.copy()
  let edits : Map[String, Array[@xml.Edit]] = Map([])
  let created : Map[String, @xml.Document] = Map([])
  let added : Map[String, Bytes] = Map([])
  fn store(path : String, markup : String) -> Unit raise @failure.Failure {
    let candidate = @xml.Document::parse(
      @utf8.encode(markup),
      path,
      self.opc.budget.xml_depth,
      self.opc.budget.entry_bytes,
    )
    if self.opc.names.contains(path.to_lower()) || self.parts.contains(path) {
      let before = self.part_xml(path)
      let node = before.nodes()[0]
      let root = candidate.nodes()[0]
      let source_tree = WordTree::new(candidate)
      let body = source_tree.children[root.id]
        .map(child => source_tree.standalone_markup(candidate, child))
        .join("")
      let (after, edit) = before.edit_source([
        {
          node: node.id,
          offset: node.opening_end - node.start,
          length: node.closing_start - node.opening_end,
          xml: body,
        },
      ])
      parts[path] = after
      edits[path] = [edit]
    } else {
      parts[path] = candidate
      created[path] = candidate
    }
  }
  fn append(path : String, markup : String) -> Unit raise @failure.Failure {
    if self.opc.names.contains(path.to_lower()) || self.parts.contains(path) {
      let (after, edit) = append_part_xml(self.part_xml(path), markup)
      parts[path] = after
      edits[path] = [edit]
    } else {
      store(
        path,
        "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\{markup}</Relationships>",
      )
    }
  }
  let rel_uri = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
  let workbook_link = if target is Some((_, chart)) {
    links
    .iter()
    .find_first(rel => {
      rel.owner == chart.part && rel.kind == rel_uri + "/package"
    })
    .unwrap().id
  } else {
    "workbook"
  }
  store(chart_part, @chart.markup(data, workbook_link))
  if reused is None {
    media[workbook_part] = bytes
    added[workbook_part] = bytes
    let rels = chart_part.split("/").to_array()
    let rels = rels[:rels.length() - 1].map(value => value.to_owned()).join("/") +
      "/_rels/" +
      rels.last().unwrap().to_owned() +
      ".rels"
    if target is Some(_) {
      let before = self.part_xml(rels)
      let node = before
        .nodes()
        .iter()
        .find_first(node => node.attribute("Id") == Some(workbook_link))
        .unwrap()
      let attribute = node.attributes
        .iter()
        .find_first(attribute => {
          attribute.uri.is_empty() && attribute.name == "Target"
        })
        .unwrap()
      let (after, edit) = before.edit_source([
        {
          node: node.id,
          offset: attribute.start - node.start,
          length: attribute.end - attribute.start,
          xml: "/" + property_attribute(workbook_part),
        },
      ])
      parts[rels] = after
      edits[rels] = [edit]
    } else {
      store(
        rels,
        "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"workbook\" Type=\"\{rel_uri}/package\" Target=\"/\{workbook_part}\"/></Relationships>",
      )
    }
  }
  if target is None {
    let rels = prefix + "_rels/" + segments.last().unwrap().to_owned() + ".rels"
    append(
      rels,
      "<Relationship xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\" Id=\"\{link}\" Type=\"\{rel_uri}/chart\" Target=\"/\{chart_part}\"/>",
    )
  }
  if target is None || reused is None {
    let markup = (if target is None {
        "<Override xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\" PartName=\"/\{chart_part}\" ContentType=\"application/vnd.openxmlformats-officedocument.drawingml.chart+xml\"/>"
      } else {
        ""
      }) +
      (if reused is None {
        "<Override xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\" PartName=\"/\{workbook_part}\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet\"/>"
      } else {
        ""
      })
    append(self.opc.names["[content_types].xml"], markup)
  }
  let candidate = { ..self, document: Some(prepared.document), parts, media, }
  let layout = @layout.paginate(probe, candidate.flow(), profile, images)
  guard layout.diagnostics.is_empty() else {
    @failure.reject(
      "unsupported-layout", "Chart requires supported complete document layout",
    )
  }
  let count = xml_part_edit_bytes(edits, created) +
    prepared.edit.bytes +
    added.values().fold(init=0, (sum, bytes) => sum + bytes.length())
  guard count <= history_byte_limit else {
    @failure.reject("limit-exceeded", "Chart edit exceeds history budget")
  }
  self.commit_edit(
    {
      ..prepared.edit,
      parts: edits,
      created,
      created_media: added,
      bytes: count,
    },
    prepared.document,
    parts~,
    media~,
  )
  self.edit_result(prepared.edit.paragraphs)
}
