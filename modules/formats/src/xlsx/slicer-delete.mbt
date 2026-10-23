///|
/// Removes a native slicer view and its drawing while retaining the cached pivot filter.
pub fn Session::delete_slicer(
  self : Session,
  revision : Int,
  sheet : String,
  name : String,
) -> Json raise @failure.Failure {
  self.delete_analysis_view(revision, sheet, name)
}

///|
fn Session::delete_analysis_view(
  self : Session,
  revision : Int,
  sheet : String,
  name : String,
  timeline~ : Bool = false,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let candidate = {
    ..self,
    parts: self.parts.copy(),
    sheets: self.sheets.copy(),
    removed: self.removed.copy(),
  }
  let edits : Array[(String, @xml.Edit)] = []
  let removed : Map[String, @xml.Document] = Map([])
  candidate.remove_analysis_view(sheet, name, edits, removed, timeline~)
  // The cache still owns native hidden-field filters after its last visible control is removed.
  self.commit(
    candidate.sheets,
    self.workbook,
    self.calculation.unwrap(),
    edits,
    self.selection,
    parts=candidate.parts,
    removed~,
    drawing_selection=self.drawing_selection,
  )
  self.query()
}

///|
fn Session::remove_analysis_view(
  self : Session,
  sheet : String,
  name : String,
  edits : Array[(String, @xml.Edit)],
  removed : Map[String, @xml.Document],
  timeline~ : Bool = false,
) -> Unit raise @failure.Failure {
  let kind = if timeline { "Timeline" } else { "Slicer" }
  let index = self.sheet_index(sheet)
  let current = self.sheets[index]
  let reason = self.dimension_reason(current)
  guard reason.is_empty() && current.state == "visible" else {
    @failure.reject(
      "protected-content",
      kind + " worksheet is protected or hidden",
    )
  }
  let part = if timeline {
    self
    .read_timelines(sheet)
    .iter()
    .find_first(control => control.name == name)
    .map(control => control.part)
  } else {
    self
    .read_slicers(sheet)
    .iter()
    .find_first(control => control.name == name)
    .map(control => control.part)
  }
  guard part is Some(part) else {
    @failure.reject(
      "invalid-operation",
      kind + " is outside the selected worksheet",
    )
  }
  let parts = self.parts
  let links = self.relationships()
  guard links.filter(link => !link.external && link.target == part) is [link] &&
    link.owner == sheet &&
    link.kind ==
    (if timeline {
      timeline_relationship_uri + "Timeline"
    } else {
      slicer_relationship_uri + "slicer"
    }) &&
    !links.any(link => link.owner == part) else {
    @failure.reject(
      "protected-content", "Shared or extended analysis resources require deletion support",
    )
  }
  let objects = self.sheet_objects(current, current.dimensions)
  let object = objects
    .iter()
    .find_first(object => {
      if timeline {
        object.timeline
        .map(timeline => timeline.control.name == name)
        .unwrap_or(false)
      } else {
        object.slicer
        .map(slicer => slicer.control.name == name)
        .unwrap_or(false)
      }
    })
  if object is Some(object) {
    for node in object.tree.document.nodes() {
      if node.start >= object.source.start &&
        node.end <= object.source.end &&
        node.name.has_suffix("Locks") &&
        flag(node, "noSelect") {
        @failure.reject("protected-content", kind + " drawing is locked")
      }
    }
    let (document, edit) = object.tree.document.edit_source([
      sheet_node_removal(object.tree, object.frame),
    ])
    parts[object.part] = document
    edits.push((object.part, edit))
  }
  let document = self.part_xml(part)
  let tree = Tree::new(document)
  let entries = if timeline {
    tree.timeline_children(document.nodes()[0].id, "timeline")
  } else {
    tree.slicer_children(document.nodes()[0].id, "slicer")
  }
  let node = entries
    .iter()
    .find_first(node => slicer_text(node, "name") == name)
    .unwrap()
  let sheet_document = if entries.length() == 1 {
    let (document, edit) = remove_analysis_reference(
      current.document,
      if timeline {
        timeline_view_extension
      } else {
        slicer_list_extension
      },
      if timeline {
        "timelineRefs"
      } else {
        "slicerList"
      },
      if timeline {
        "timelineRef"
      } else {
        "slicer"
      },
      link.id,
      payload_uri=if timeline { timeline_uri } else { slicer_uri },
    )
    edits.push((sheet, edit))
    self.detach_analysis_resource(sheet, part, link.id, parts, removed, edits)
    document
  } else {
    let (document, edit) = document.edit_source([sheet_node_removal(tree, node)])
    parts[part] = document
    edits.push((part, edit))
    current.document
  }
  let sheets = self.sheets.copy()
  sheets[index] = Sheet::read(
    sheet,
    current.name,
    current.state,
    sheet_document,
    self.strings,
    self.styles.length(),
  )
  let candidate = { ..self, sheets, parts, }
  if timeline {
    ignore(candidate.read_timelines(sheet))
  } else {
    ignore(candidate.read_slicers(sheet))
  }
  ignore(candidate.sheet_objects(sheets[index], current.dimensions))
  self.sheets = sheets
}

///|
fn remove_analysis_reference(
  document : @xml.Document,
  extension : String,
  container : String,
  child : String,
  id : String,
  payload_uri~ : String = slicer_uri,
) -> (@xml.Document, @xml.Edit) raise @failure.Failure {
  let tree = Tree::new(document)
  let list = tree.one(document.nodes()[0].id, "extLst").unwrap()
  let extension = tree
    .all(list.id, "ext")
    .iter()
    .find_first(node => {
      node
      .attribute("uri")
      .map(uri => uri.to_upper() == extension)
      .unwrap_or(false)
    })
    .unwrap()
  let container = tree.picture_node(extension.id, container, uri=payload_uri)
  let entries = tree.children
    .get(container.id)
    .unwrap_or([])
    .filter(node => node.uri == payload_uri && node.name == child)
  let entry = entries
    .iter()
    .find_first(node => {
      node.attribute(
        "id",
        uri=relationship_uri[:relationship_uri.length() - 1].to_owned(),
      ) ==
      Some(id)
    })
    .unwrap()
  let node = if entries.length() != 1 {
    entry
  } else if tree.children.get(list.id).unwrap_or([]).length() == 1 {
    list
  } else {
    extension
  }
  let source = document.source()
  guard !source[node.start:node.end].contains("<!--") &&
    !source[node.start:node.end].contains("<?") else {
    @failure.reject(
      "protected-content", "Analysis reference annotations require preservation support",
    )
  }
  document.edit_source([sheet_node_removal(tree, node)])
}

///|
fn Session::detach_analysis_resource(
  self : Session,
  owner : String,
  part : String,
  id : String,
  parts : Map[String, @xml.Document],
  removed : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
) -> Unit raise @failure.Failure {
  for path in [workbook_relations(owner), "[Content_Types].xml"] {
    let original = self.part_xml(path)
    let tree = Tree::new(original)
    let matches = original
      .nodes()
      .filter(node => {
        node.parent == original.nodes()[0].id &&
        (if path == "[Content_Types].xml" {
          node
          .attribute("PartName")
          .map(name => name.to_lower() == "/" + part.to_lower())
          .unwrap_or(false)
        } else {
          node.attribute("Id") == Some(id)
        })
      })
    guard matches is [entry] else {
      @failure.reject(
        "protected-content", "Analysis resource entry is ambiguous",
      )
    }
    let (document, edit) = original.edit_source([
      sheet_node_removal(tree, entry),
    ])
    parts[path] = document
    edits.push((path, edit))
  }
  // Keep the independent drawing part and other relationships, including empty containers.
  for path in [part, workbook_relations(part)] {
    if parts.contains(path) || self.opc.names.contains(path.to_lower()) {
      removed[path] = self.part_xml(path)
      parts.remove(path)
      if self.opc.names.contains(path.to_lower()) &&
        !self.removed.contains(path) {
        self.removed.push(path)
      }
    }
  }
}
