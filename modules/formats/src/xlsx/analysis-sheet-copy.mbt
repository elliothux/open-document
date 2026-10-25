///|
fn copied_analysis_identity(
  node : @xml.Node,
  names : Set[String],
  uids : Map[String, Bool],
) -> (String, Array[@xml.SourceChange]) raise @failure.Failure {
  let original = slicer_text(node, "name")
  let name = for index in 1..<=(names.length() + 1) {
    let suffix = "_" + index.to_string()
    let mut end = original.length().min(255 - suffix.length())
    if end > 0 && original[end - 1] >= 0xd800 && original[end - 1] <= 0xdbff {
      end -= 1
    }
    let name = original[:end].to_owned() + suffix
    if !names.contains(name.to_upper()) {
      break name
    }
  } nobreak {
    @failure.reject("limit-exceeded", "Copied analysis names exhausted")
  }
  names.add(name.to_upper())
  let changes = metadata_changes(node, [("name", encoded_text(name))])
  for attribute in node.attributes {
    if attribute.name == "uid" &&
      attribute.uri ==
      "http://schemas.microsoft.com/office/spreadsheetml/2016/revision10" {
      let kind = if node.uri == slicer_uri {
        if node.name == "slicer" {
          "00000001"
        } else {
          "00000002"
        }
      } else if node.name == "timeline" {
        "00000003"
      } else {
        "00000004"
      }
      let value = slicer_creation_uid_value(uids, uids.length(), kind)
      uids[value] = true
      changes.push({
        node: node.id,
        offset: attribute.start - node.start,
        length: attribute.end - attribute.start,
        xml: escaped_attribute(value),
      })
    }
  }
  (name, changes)
}

///|
fn check_analysis_copy_budget(
  created : Map[String, @xml.Document],
  sheet : @xml.Document,
) -> Unit raise @failure.Failure {
  guard created
    .values()
    .fold(init=sheet.source().length().to_int64() * 2, (total, document) => {
      total + document.source().length().to_int64() * 2
    }) <=
    4194304L else {
    @failure.reject(
      "limit-exceeded", "Copied analysis resources exceed history budget",
    )
  }
}

///|
fn Session::copy_sheet_analysis(
  self : Session,
  source : Sheet,
  target : Sheet,
  tab : String,
  remapped : Map[String, String],
  parts : Map[String, @xml.Document],
  created : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
  workbook : @xml.Document,
) -> (@xml.Document, @xml.Document) raise @failure.Failure {
  let local_slicers = self.read_slicers(source.id)
  let local_timelines = self.read_timelines(source.id)
  let pivots = self.pivot_locations()
  let links = self.relationships()
  let names : Set[String] = Set([])
  let uids : Map[String, Bool] = Map([])
  let known = self.analysis_parts()
  for part in known {
    for node in self.part_xml(part).nodes() {
      if (
          node.uri == slicer_uri &&
          ["slicer", "slicerCacheDefinition"].contains(node.name)
        ) ||
        (
          node.uri == timeline_uri &&
          ["timeline", "timelineCacheDefinition"].contains(node.name)
        ) {
        names.add(slicer_text(node, "name").to_upper())
        if node.attribute(
            "uid",
            uri="http://schemas.microsoft.com/office/spreadsheetml/2016/revision10",
          )
          is Some(uid) {
          uids[uid.to_upper()] = true
        }
      }
    }
  }
  let mut workbook = workbook
  let caches : Map[String, String] = Map([])
  for part in known {
    let original = self.part_xml(part)
    let root = original.nodes()[0]
    let timeline = root.uri == timeline_uri &&
      root.name == "timelineCacheDefinition"
    if !timeline &&
      !(root.uri == slicer_uri && root.name == "slicerCacheDefinition") {
      continue
    }
    let uri = if timeline { timeline_uri } else { slicer_uri }
    let connections = original
      .nodes()
      .filter(node => node.uri == uri && node.name == "pivotTable")
    if !connections.any(node => {
        self.slicer_pivot_sheet(node.attribute("tabId").unwrap_or("")) ==
        source.id
      }) &&
      !local_slicers.any(view => view.cache.part == part) &&
      !local_timelines.any(view => view.cache.part == part) {
      continue
    }
    let kind = if timeline { "TimelineCache" } else { "slicerCache" }
    guard links.filter(link => !link.external && link.target == part) is [owner] &&
      owner.owner == self.main &&
      owner.kind ==
      (if timeline {
        timeline_relationship_uri
      } else {
        slicer_relationship_uri
      }) +
      kind &&
      !links.any(link => link.owner == part) else {
      @failure.reject(
        "protected-content", "Analysis cache ownership requires copying support",
      )
    }
    let (name, changes) = copied_analysis_identity(root, names, uids)
    for node in connections {
      if self.slicer_pivot_sheet(node.attribute("tabId").unwrap_or("")) !=
        source.id {
        continue
      }
      let original_name = slicer_text(node, "name")
      let pivot = pivots
        .iter()
        .find_first(pivot => {
          pivot.sheet == source.id && pivot.name == original_name
        })
        .unwrap()
      let copy = created[remapped[pivot.part]].nodes()[0]
      changes.append(
        metadata_changes(node, [
          ("tabId", tab),
          ("name", copy.attribute("name").unwrap()),
        ]),
      )
    }
    let document = original.edit_source(changes).0
    let (_, relation) = self.create_sheet_resource(
      self.main,
      kind,
      document.source(),
      parts,
      created,
      edits,
    )
    let (updated, edit) = analysis_reference(
      workbook,
      if timeline {
        timeline_cache_extension
      } else {
        slicer_cache_extension
      },
      if timeline {
        "timelineCacheRefs"
      } else {
        "slicerCaches"
      },
      if timeline {
        "timelineCacheRef"
      } else {
        "slicerCache"
      },
      relation,
      payload_uri=uri,
    )
    workbook = updated
    edits.push((self.main, edit))
    caches[part] = name
    check_analysis_copy_budget(created, target.document)
  }
  let views = Set::from_array(
    local_slicers.map(view => view.part) +
    local_timelines.map(view => view.part),
  ).to_array()
  views.sort()
  let identities : Map[(String, String), String] = Map([])
  let references : Map[String, String] = Map([])
  for part in views {
    let original = self.part_xml(part)
    let timeline = original.nodes()[0].uri == timeline_uri
    let uri = if timeline { timeline_uri } else { slicer_uri }
    let kind = if timeline { "Timeline" } else { "slicer" }
    guard links.filter(link => !link.external && link.target == part) is [owner] &&
      owner.owner == source.id &&
      owner.kind ==
      (if timeline {
        timeline_relationship_uri
      } else {
        slicer_relationship_uri
      }) +
      kind &&
      !links.any(link => link.owner == part) else {
      @failure.reject(
        "protected-content", "Analysis view ownership requires copying support",
      )
    }
    let changes : Array[@xml.SourceChange] = []
    for node in original.nodes() {
      if node.uri != uri ||
        node.name != (if timeline { "timeline" } else { "slicer" }) {
        continue
      }
      let (name, identity) = copied_analysis_identity(node, names, uids)
      changes.append(identity)
      let cache = if timeline {
        local_timelines
        .iter()
        .find_first(view => view.name == slicer_text(node, "name"))
        .unwrap().cache.part
      } else {
        local_slicers
        .iter()
        .find_first(view => view.name == slicer_text(node, "name"))
        .unwrap().cache.part
      }
      changes.append(
        metadata_changes(node, [("cache", encoded_text(caches[cache]))]),
      )
      identities[(
        if timeline {
          timeline_drawing_uri
        } else {
          slicer_drawing_uri
        },
        slicer_text(node, "name"),
      )] = name
    }
    let document = original.edit_source(changes).0
    let (_, relation) = self.create_sheet_resource(
      target.id,
      kind,
      document.source(),
      parts,
      created,
      edits,
    )
    references[owner.id] = relation
    check_analysis_copy_budget(created, target.document)
  }
  let sheet_changes : Array[@xml.SourceChange] = []
  let rel_uri = relationship_uri[:relationship_uri.length() - 1].to_owned()
  for node in target.document.nodes() {
    if !((node.uri == slicer_uri && node.name == "slicer") ||
      (node.uri == timeline_uri && node.name == "timelineRef")) {
      continue
    }
    for attribute in node.attributes {
      if attribute.uri == rel_uri &&
        attribute.name == "id" &&
        references.get(attribute.value) is Some(id) {
        sheet_changes.push({
          node: node.id,
          offset: attribute.start - node.start,
          length: attribute.end - attribute.start,
          xml: escaped_attribute(id),
        })
      }
    }
  }
  let document = if sheet_changes.is_empty() {
    target.document
  } else {
    let (document, edit) = target.document.edit_source(sheet_changes)
    edits.push((target.id, edit))
    document
  }
  if !references.is_empty() {
    let path = workbook_relations(target.id)
    let original = parts[path]
    let tree = Tree::new(original)
    let removed = original
      .nodes()
      .filter(node => {
        node.attribute("Id").map(id => references.contains(id)).unwrap_or(false)
      })
    let changes : Array[@xml.SourceChange] = []
    for node in removed {
      changes.push(sheet_node_removal(tree, node))
    }
    let (document, edit) = original.edit_source(changes)
    parts[path] = document
    edits.push((path, edit))
  }
  if self.picture_drawing(source) is Some((part, _)) && !identities.is_empty() {
    let path = remapped[part]
    let original = parts[path]
    let tree = Tree::new(original)
    let changes : Array[@xml.SourceChange] = []
    for node in original.nodes() {
      if !((node.uri == slicer_drawing_uri && node.name == "slicer") ||
        (node.uri == timeline_drawing_uri && node.name == "timeslicer")) {
        continue
      }
      let name = identities[(node.uri, slicer_text(node, "name"))]
      changes.append(metadata_changes(node, [("name", encoded_text(name))]))
      let mut parent = node.parent
      while parent >= 0 &&
            !(tree.nodes[parent].uri == picture_uri &&
            tree.nodes[parent].name == "graphicFrame") {
        parent = tree.nodes[parent].parent
      }
      guard parent >= 0 else {
        @failure.reject(
          "protected-content", "Analysis graphic identity requires copying support",
        )
      }
      let identity = tree.picture_node(
        tree.picture_node(parent, "nvGraphicFramePr").id,
        "cNvPr",
      )
      guard identity.attributes.all(attribute => {
          attribute.uri.is_empty() &&
          ["id", "name", "descr", "title", "hidden"].contains(attribute.name)
        }) &&
        !original
        .nodes()
        .any(child => {
          child.start >= tree.nodes[parent].start &&
          child.end <= tree.nodes[parent].end &&
          child.name.has_suffix("Locks") &&
          flag(child, "noCopy")
        }) else {
        @failure.reject(
          "protected-content", "Analysis graphic copying is locked or extended",
        )
      }
      changes.append(metadata_changes(identity, [("name", name)]))
    }
    let (document, edit) = original.edit_source(changes)
    parts[path] = document
    edits.push((path, edit))
  }
  let candidate = {
    ..self,
    workbook,
    parts,
    sheets: [..self.sheets, { ..target, document, }],
  }
  ignore(candidate.read_slicers(target.id))
  ignore(candidate.read_timelines(target.id))
  (workbook, document)
}
