///|
fn Session::remove_pivot_cache_reference(
  self : Session,
  pivot : PivotLocation,
) -> (@xml.Document, @xml.Edit) raise @failure.Failure {
  let links = self.relationships()
  let part = pivot.part
  let tree = Tree::new(self.workbook)
  let parent = tree.one(tree.root("workbook").id, "pivotCaches").unwrap()
  let root = self.part_xml(part).nodes()[0]
  let cache_id = natural(root.attribute("cacheId").unwrap_or(""), 2147483647)
  let caches = tree.all(parent.id, "pivotCache")
  guard caches.filter(node => {
      natural(node.attribute("cacheId").unwrap_or(""), 2147483647) == cache_id
    })
    is [entry] else {
    @failure.reject(
      "malformed-xlsx", "Missing unique workbook pivot cache entry",
    )
  }
  guard links.filter(link => {
      link.owner == self.main && link.target == pivot.cache && !link.external
    })
    is [cache_link] &&
    caches
    .filter(node => {
      node.attribute(
        "id",
        uri=relationship_uri[:relationship_uri.length() - 1].to_owned(),
      ) ==
      Some(cache_link.id)
    })
    .length() ==
    1 else {
    @failure.reject(
      "protected-content", "Shared workbook cache entries require coordinated deletion",
    )
  }
  conditional_node(tree, parent, [], ["pivotCache"])
  guard entry.attributes.all(attribute => {
      (attribute.uri.is_empty() && attribute.name == "cacheId") ||
      (
        attribute.uri ==
        relationship_uri[:relationship_uri.length() - 1].to_owned() &&
        attribute.name == "id"
      )
    }) &&
    tree.children.get(entry.id).unwrap_or([]).is_empty() else {
    @failure.reject(
      "protected-content", "Extended workbook cache entry requires deletion support",
    )
  }
  let node = if caches.length() == 1 { parent } else { entry }
  guard !self.workbook.source()[node.start:node.end].contains("<!--") &&
    !self.workbook.source()[node.start:node.end].contains("<?") else {
    @failure.reject(
      "protected-content", "Pivot cache comments require preservation support",
    )
  }
  let (workbook, workbook_edit) = self.workbook.edit_source([
    sheet_node_removal(tree, node),
  ])
  (workbook, workbook_edit)
}
