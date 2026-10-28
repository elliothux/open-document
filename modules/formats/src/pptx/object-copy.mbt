///|
priv struct CopiedObjects {
  changes : Array[@xml.SourceChange]
  selection : Selection
  identities : Array[String]
  next : Int64
  documents : Map[String, @xml.Document]
  workbooks : Map[String, Bytes]
  relationships : String
  types : String
}

///|
fn Session::copy_objects(
  self : Session,
  dx : Double,
  dy : Double,
) -> CopiedObjects raise @failure.Failure {
  guard self.selection.mode == "object" else {
    @failure.reject(
      "invalid-operation", "Object copying requires object selection",
    )
  }
  let slide = self.current()
  let checked = self.transform_objects(action="duplicate")
  let selected = self.selection.objects
  let objects = slide.objects.filter(object => selected.contains(object.id))
  let changes : Array[@xml.SourceChange] = []
  let mut units = 0
  for object in objects {
    let reason = self.object_edit_reason(object, "duplicate")
    guard reason.is_empty() else {
      @failure.reject("protected-content", reason)
    }
    units += object.source.node.end - object.source.node.start
    guard units <= 2097152 else {
      @failure.reject("limit-exceeded", "Copied objects exceed history budget")
    }
    let geometry = object.geometry.unwrap()
    let inverse = object.source.parent_frame().inverse()
    let target = {
      ..geometry,
      x: geometry.x + inverse.a * dx + inverse.c * dy,
      y: geometry.y + inverse.b * dx + inverse.d * dy,
    }
    validate_object_box(
      target.x,
      target.y,
      target.width,
      target.height,
      line_shape(object.preset),
    )
    changes.append(transform_changes(object, target))
  }
  let (positioned, _) = slide.tree.document.edit_source(changes)
  let content = StringBuilder()
  content.write_string("<p:spTree xmlns:p=\"\{presentation_uri}\">")
  units = 0
  for object in objects {
    let markup = slide.tree.standalone_markup(positioned, object.source.node.id)
    units += markup.length()
    guard units <= 2097152 else {
      @failure.reject(
        "limit-exceeded", "Copied object namespaces exceed history budget",
      )
    }
    content.write_string(markup)
  }
  content.write_string("</p:spTree>")
  let source = @xml.Document::parse(
    @utf8.encode(content.to_string()),
    slide.tree.part,
    self.budget.xml_depth,
    self.budget.entry_bytes,
  )
  // Reuse slide copying's identity and local-reference remapping for the selected subtrees.
  let (copied, next) = copy_slide_objects(
    Tree::new(slide.tree.part, source),
    slide.tree.part,
    self.reserved_object_identities(),
    self.object_sequence,
    self.budget,
  )
  let identities : Map[String, String] = Map([])
  let originals = source
    .nodes()
    .filter(node => node.uri == presentation_uri && node.name == "cNvPr")
  let copies = copied
    .nodes()
    .filter(node => node.uri == presentation_uri && node.name == "cNvPr")
  for index, node in originals {
    identities[slide.tree.part +
    "#" +
    source_identity(node.attribute("id").unwrap_or(""))] = slide.tree.part +
      "#" +
      source_identity(copies[index].attribute("id").unwrap_or(""))
  }
  let documents : Map[String, @xml.Document] = Map([])
  let workbooks : Map[String, Bytes] = Map([])
  let relationships = StringBuilder()
  let types = StringBuilder()
  let copied_tree = Tree::new(slide.tree.part, copied)
  let chart_changes : Array[@xml.SourceChange] = []
  let links = self.relationships()
  let reserved : Map[String, Bool] = Map([])
  for link in links {
    if link.owner == slide.tree.part {
      reserved[link.id] = true
    }
  }
  for object in slide.objects {
    if identities.contains(object.id) && object.chart is Some(chart) {
      let id = identities[object.id].split("#").last().unwrap().to_owned()
      let (part, overrides) = self.copy_chart_parts(
        chart, id, documents, workbooks,
      )
      types.write_string(overrides)
      let mut sequence = 0
      let mut link = "odCopyChart" + id
      while reserved.contains(link) {
        sequence += 1
        guard sequence <= self.budget.entries else {
          @failure.reject(
            "limit-exceeded", "Copied chart relationships exhausted",
          )
        }
        link = "odCopyChart" + id + "_" + sequence.to_string()
      }
      reserved[link] = true
      relationships <+
        "<Relationship xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\" Id=\"\{link}\" Type=\"\{relationship_uri}/chart\" Target=\"/\{xml_attribute(part)}\"/>"
      let identity = copied
        .nodes()
        .iter()
        .find_first(n => {
          n.uri == presentation_uri &&
          n.name == "cNvPr" &&
          n.attribute("id") == Some(id)
        })
        .unwrap()
      let frame : Ref = {
        tree: copied_tree,
        node: copied_tree.nodes[copied_tree.nodes[identity.parent].parent],
      }
      let reference = frame
        .child("graphic")
        .unwrap()
        .child("graphicData")
        .unwrap()
        .child("chart", uri=chart_uri)
        .unwrap()
      let attr = reference.node.attributes
        .iter()
        .find_first(a => a.uri == relationship_uri && a.name == "id")
        .unwrap()
      chart_changes.push({
        node: reference.node.id,
        offset: attr.start - reference.node.start,
        length: attr.end - attr.start,
        xml: link,
      })
    }
  }
  let copied = if chart_changes.is_empty() {
    copied
  } else {
    copied.edit_source(chart_changes).0
  }
  let root = copied.nodes()[0]
  {
    changes: [
      object_insertion(
        slide.tree,
        copied.source()[root.opening_end:root.closing_start].to_owned(),
        parent=Some(slide.tree.nodes[checked[0].source.node.parent]),
      ),
      ..self.copy_media_settings(slide, identities),
    ],
    selection: {
      ..self.selection,
      objects: selected.map(id => identities[id]),
      object: identities[self.selection.object],
      anchor: 0,
      focus: 0,
    },
    identities: identities.values().to_array(),
    next,
    documents,
    workbooks,
    relationships: relationships.to_string(),
    types: types.to_string(),
  }
}

///|
fn Session::duplicate_objects(
  self : Session,
  dx : Double,
  dy : Double,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  guard [dx, dy].all(v => !v.is_nan() && !v.is_inf() && v.abs() <= 14400) else {
    @failure.reject("invalid-transform", "Invalid duplication offset")
  }
  if self.selection.object.is_empty() {
    return self.query()
  }
  let original = self.current()
  let copied = self.copy_objects(dx, dy)
  let parts = self.parts.copy()
  let media = self.media.copy()
  for path, document in copied.documents {
    parts[path] = document
  }
  for path, bytes in copied.workbooks {
    media[path] = bytes
  }
  let created = copied.documents.copy()
  let edits : Array[(String, @xml.Edit)] = []
  for
    (path, markup) in [
      (relationship_part(original.tree.part), copied.relationships),
      ("[Content_Types].xml", copied.types),
    ] {
    if !markup.is_empty() {
      self.append_chart_xml(path, markup, parts, created, edits)
    }
  }
  let (document, edit) = original.tree.document.edit_source(copied.changes)
  edits.push((original.tree.part, edit))
  let candidate = read_slide(
    self.opc,
    self.main,
    self.cache,
    Tree::new(original.tree.part, document),
    index=self.source_index(original.tree.part),
    date_time=self.date_time,
    parts~,
  )
  let candidate = candidate
    .group_bounds(candidate.changed_group_members(original))
    .connector_bounds(original)
  // Measure fonts and budgets; a duplicate retains its source overflow diagnostics.
  for id in copied.identities {
    let object = candidate.object(id)
    if object.chart is Some(chart) {
      let geometry = object.geometry.unwrap()
      ignore(chart.paint(geometry.width, geometry.height, probe, profile))
    } else if object.table is Some(_) {
      ignore(object.paint_table(probe, profile))
    } else {
      ignore(fit_text(object, object.geometry.unwrap(), probe, profile))
    }
  }
  self.commit_page(
    candidate,
    edits,
    copied.selection,
    parts~,
    media~,
    created_parts=created,
    created_media=copied.workbooks,
    probe~,
    profile~,
  )
  self.object_sequence = copied.next
  self.query()
}
