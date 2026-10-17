///|
fn sheet_node_removal(tree : Tree, node : @xml.Node) -> @xml.SourceChange {
  {
    node: node.parent,
    offset: node.start - tree.nodes[node.parent].start,
    length: node.end - node.start,
    xml: "",
  }
}

///|
fn Session::prepare_sheet_delete(
  self : Session,
  index : Int,
  parts : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
) -> Map[String, @xml.Document] raise @failure.Failure {
  let reason = self.sheet_rename_reason()
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let deleted = self.sheets[index]
  guard self.sheets
    .iter()
    .any(sheet => sheet.id != deleted.id && sheet.state == "visible") else {
    @failure.reject(
      "invalid-sheet", "At least one visible worksheet is required",
    )
  }
  let names = [deleted.id]
  let relations = workbook_relations(deleted.id)
  if self.parts.contains(relations) ||
    self.opc.names.contains(relations.to_lower()) {
    names.push(relations)
  }
  let links = self.relationships()
  if self.read_sheet_notes(deleted) is Some(notes) {
    names.push(notes.part)
    if notes.vml is Some((part, _, _)) {
      names.push(part)
    }
    for part in [notes.part] {
      let path = workbook_relations(part)
      if self.parts.contains(path) || self.opc.names.contains(path.to_lower()) {
        names.push(path)
      }
    }
  }
  for link in links {
    if link.owner == self.main && link.kind == relationship_uri + "calcChain" {
      guard !link.external else {
        @failure.reject("protected-content", "External calculation chain")
      }
      names.push(link.target)
      let path = workbook_relations(link.target)
      if self.parts.contains(path) || self.opc.names.contains(path.to_lower()) {
        names.push(path)
      }
    }
  }
  let removed : Map[String, @xml.Document] = Map([])
  let mut bytes = 0L
  for name in names {
    guard !removed.contains(name) else {
      @failure.reject(
        "protected-content", "Cyclic worksheet resource ownership",
      )
    }
    let document = if name == deleted.id {
      deleted.document
    } else {
      self.part_xml(name)
    }
    bytes += document.source().length().to_int64() * 2
    guard bytes <= 4194304L else {
      @failure.reject(
        "limit-exceeded", "Deleted worksheet exceeds history budget",
      )
    }
    removed[name] = document
  }
  let ids : Array[String] = []
  for link in links {
    if link.external ||
      !removed.contains(link.target) ||
      removed.contains(link.owner) {
      continue
    }
    guard link.owner == self.main &&
      [relationship_uri + "worksheet", relationship_uri + "calcChain"].contains(
        link.kind,
      ) else {
      @failure.reject(
        "protected-content", "Unknown incoming worksheet resource reference",
      )
    }
    ids.push(link.id)
  }
  for path in [workbook_relations(self.main), "[Content_Types].xml"] {
    let original = self.part_xml(path)
    let tree = Tree::new(original)
    let root = original.nodes()[0]
    let changes = original
      .nodes()
      .iter()
      .filter(node => {
        node.parent == root.id &&
        (if path == "[Content_Types].xml" {
          node
          .attribute("PartName")
          .map(name => {
            name.has_prefix("/") &&
            names.any(path => path.to_lower() == name[1:].to_owned().to_lower())
          })
          .unwrap_or(false)
        } else {
          node.attribute("Id").map(id => ids.contains(id)).unwrap_or(false)
        })
      })
      .map(node => sheet_node_removal(tree, node))
      .collect()
    if !changes.is_empty() {
      let (document, edit) = original.edit_source(changes)
      parts[path] = document
      edits.push((path, edit))
    }
  }
  for name in names {
    parts.remove(name)
  }
  removed
}
