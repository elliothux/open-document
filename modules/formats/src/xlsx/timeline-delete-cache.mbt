///|
fn Session::remove_timeline_data_cache(
  self : Session,
  part : String,
  edits : Array[(String, @xml.Edit)],
  removed : Map[String, @xml.Document],
) -> Unit raise @failure.Failure {
  let links = self.relationships()
  guard links.filter(link => !link.external && link.target == part)
    is [incoming] &&
    incoming.owner == self.main &&
    incoming.kind == relationship_uri + "pivotCacheDefinition" else {
    @failure.reject(
      "protected-content", "Shared timeline date cache requires deletion support",
    )
  }
  let document = self.part_xml(part)
  let outgoing = links.filter(link => link.owner == part)
  guard outgoing.length() <= 1 &&
    outgoing.all(link => {
      !link.external &&
      link.kind == relationship_uri + "pivotCacheRecords" &&
      document.nodes()[0].attribute(
        "id",
        uri=relationship_uri[:relationship_uri.length() - 1].to_owned(),
      ) ==
      Some(link.id)
    }) &&
    (
      !outgoing.is_empty() ||
      document.nodes()[0].attribute(
        "id",
        uri=relationship_uri[:relationship_uri.length() - 1].to_owned(),
      )
      is None
    ) else {
    @failure.reject(
      "protected-content", "Extended timeline date cache requires deletion support",
    )
  }
  for link in outgoing {
    if links
      .filter(other => !other.external && other.target == link.target)
      .length() ==
      1 {
      guard !links.any(other => other.owner == link.target) &&
        self
        .part_xml("[Content_Types].xml")
        .nodes()
        .filter(node => {
          node.name == "Override" &&
          node
          .attribute("PartName")
          .map(name => name.to_lower() == "/" + link.target.to_lower())
          .unwrap_or(false)
        })
        is [content] &&
        content.attribute("ContentType") ==
        Some(
          "application/vnd.openxmlformats-officedocument.spreadsheetml.pivotCacheRecords+xml",
        ) else {
        @failure.reject(
          "protected-content", "Extended timeline date records require deletion support",
        )
      }
      self.detach_analysis_resource(
        part,
        link.target,
        link.id,
        self.parts,
        removed,
        edits,
      )
    }
  }
  let tree = Tree::new(self.workbook)
  guard self.workbook
    .nodes()
    .filter(node => {
      node.uri == spreadsheet_uri &&
      node.name == "pivotCache" &&
      node.attribute(
        "id",
        uri=relationship_uri[:relationship_uri.length() - 1].to_owned(),
      ) ==
      Some(incoming.id)
    })
    is [entry] else {
    @failure.reject(
      "protected-content", "Timeline date cache reference is ambiguous",
    )
  }
  guard entry.attributes.length() == 2 &&
    entry.attribute("cacheId") is Some(_) &&
    tree.children.get(entry.id).unwrap_or([]).is_empty() else {
    @failure.reject(
      "protected-content", "Extended timeline date cache reference requires support",
    )
  }
  let parent = tree.nodes[entry.parent]
  let entries = tree.all(parent.id, "pivotCache")
  let node = if parent.uri == spreadsheet_uri &&
    parent.name == "pivotCaches" &&
    parent.parent == 0 {
    conditional_node(tree, parent, [], ["pivotCache"])
    if entries.length() == 1 {
      parent
    } else {
      entry
    }
  } else {
    let ext = tree.nodes[parent.parent]
    let list = tree.nodes[ext.parent]
    guard parent.uri == timeline_uri &&
      parent.name == "timelineCachePivotCaches" &&
      parent.attributes.is_empty() &&
      tree.children.get(parent.id).unwrap_or([]).length() == entries.length() &&
      ext.uri == spreadsheet_uri &&
      ext.name == "ext" &&
      ext
      .attribute("uri")
      .map(uri => uri.to_upper() == "{A2CB5862-8E78-49C6-8D9D-AF26E26ADB89}")
      .unwrap_or(false) &&
      tree.children.get(ext.id).unwrap_or([]).length() == 1 &&
      list.name == "extLst" &&
      list.uri == spreadsheet_uri &&
      list.parent == 0 else {
      @failure.reject(
        "protected-content", "Unknown timeline date cache directory requires preservation support",
      )
    }
    if entries.length() > 1 {
      entry
    } else if tree.children.get(list.id).unwrap_or([]).length() > 1 {
      ext
    } else {
      list
    }
  }
  let source = self.workbook.source()
  guard !source[node.start:node.end].contains("<!--") &&
    !source[node.start:node.end].contains("<?") else {
    @failure.reject(
      "protected-content", "Timeline date directory annotations require preservation support",
    )
  }
  let (workbook, edit) = self.workbook.edit_source([
    sheet_node_removal(tree, node),
  ])
  self.workbook = workbook
  edits.push((self.main, edit))
  self.detach_analysis_resource(
    self.main,
    part,
    incoming.id,
    self.parts,
    removed,
    edits,
  )
}
