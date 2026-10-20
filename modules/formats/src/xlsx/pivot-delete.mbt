///|
/// Removes a supported independent pivot, its owned resources and result values in one history entry.
pub fn Session::delete_pivot(
  self : Session,
  revision : Int,
  sheet : String,
  part : String,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let index = self.sheet_index(sheet)
  let current = self.sheets[index]
  guard self.read_only.is_empty() &&
    !current.locked &&
    current.state == "visible" else {
    @failure.reject(
      "protected-content", "Pivot destination is protected or hidden",
    )
  }
  guard self
    .pivot_locations()
    .iter()
    .find_first(p => p.sheet == sheet && p.part == part)
    is Some(pivot) else {
    @failure.reject(
      "invalid-operation", "Pivot is outside the selected worksheet",
    )
  }
  guard (pivot.range.bottom - pivot.range.top + 1).to_int64() *
    (pivot.range.right - pivot.range.left + 1).to_int64() <=
    32768 else {
    @failure.reject("limit-exceeded", "Pivot deletion exceeds output budget")
  }
  let (_, records) = self.pivot_settings(pivot)
  guard !current.merges.any(range => range.intersects(pivot.range)) &&
    !self
    .table_definitions(self.sheets, self.workbook, self.parts)
    .any(table => table.sheet == sheet && table.range.intersects(pivot.range)) else {
    @failure.reject(
      "protected-content", "Pivot output overlaps a merged or structured range",
    )
  }
  let links = self.relationships()
  let owned = [part, pivot.cache, records]
  let paths = owned.copy()
  for owner in owned {
    let path = workbook_relations(owner)
    if self.parts.contains(path) || self.opc.names.contains(path.to_lower()) {
      paths.push(self.opc.names.get(path.to_lower()).unwrap_or(path))
    }
  }
  // Incoming links outside this ownership graph can include slicers or timelines.
  for link in links {
    if owned.contains(link.owner) {
      guard !link.external &&
        (
          (
            link.owner == part &&
            link.kind == relationship_uri + "pivotCacheDefinition" &&
            link.target == pivot.cache
          ) ||
          (
            link.owner == pivot.cache &&
            link.kind == relationship_uri + "pivotCacheRecords" &&
            link.target == records
          )
        ) else {
        @failure.reject(
          "protected-content", "Unknown outgoing pivot resource requires deletion support",
        )
      }
    } else if !link.external && paths.contains(link.target) {
      guard (
          link.owner == sheet &&
          link.target == part &&
          link.kind == relationship_uri + "pivotTable"
        ) ||
        (
          link.owner == self.main &&
          link.target == pivot.cache &&
          link.kind == relationship_uri + "pivotCacheDefinition"
        ) else {
        @failure.reject(
          "protected-content", "Shared or linked pivot resources require coordinated deletion",
        )
      }
    }
  }
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
  let updates : Map[String, CellContent] = Map([])
  let indices : Map[String, Int] = Map([])
  let (normal, styles, style_edits) = self.normal_style()
  let style_parts = self.parts.copy()
  for (path, document, _) in style_edits {
    style_parts[path] = document
  }
  for row in pivot.range.top..<=pivot.range.bottom {
    for column in pivot.range.left..<=pivot.range.right {
      updates[Address::{ row, column, }.name()] = {
        value: Blank,
        formula: None,
        keep_shared: false,
      }
      indices[Address::{ row, column, }.name()] = normal
    }
  }
  let formatting : StyleEdit = {
    indices,
    styles,
    parts: style_parts,
    edits: style_edits.map(entry => (entry.0, entry.2)),
    created_parts: Map([]),
  }
  let plan = self.prepare_cells(
    Map([(index, updates)]),
    styles=Map([(index, indices)]),
    formatting=Some(formatting),
    validate_values=false,
  )
  let parts = plan.parts
  let edits = plan.edits
  let changes = clear_rules(
    plan.sheets[index].document,
    pivot.range,
    true,
    table_parts=true,
  )
  if !changes.is_empty() {
    let (document, edit) = plan.sheets[index].document.edit_source(changes)
    plan.sheets[index] = Sheet::read(
      sheet,
      current.name,
      current.state,
      document,
      self.strings,
      plan.styles.length(),
    )
    edits.push((sheet, edit))
  }
  if self.read_sheet_notes(current) is Some(notes) {
    let addresses : Map[String, Address?] = Map([])
    for note in notes.entries {
      if pivot.range.contains(note.address) {
        addresses[note.address.name()] = None
      }
    }
    update_note_addresses(notes, addresses, parts, edits)
  }
  edits.push((self.main, workbook_edit))
  let removed : Map[String, @xml.Document] = Map([])
  for path in paths {
    removed[path] = self.part_xml(path)
    parts.remove(path)
  }
  for
    path in [
      workbook_relations(sheet),
      workbook_relations(self.main),
      "[Content_Types].xml",
    ] {
    let original = parts.get(path).unwrap_or_else(() => self.part_xml(path))
    let tree = Tree::new(original)
    let root = original.nodes()[0]
    let owner = if path == workbook_relations(sheet) {
      sheet
    } else {
      self.main
    }
    let ids = links
      .filter(link => {
        link.owner == owner && !link.external && owned.contains(link.target)
      })
      .map(link => link.id)
    let selected = original
      .nodes()
      .filter(node => {
        node.parent == root.id &&
        (if path == "[Content_Types].xml" {
          node
          .attribute("PartName")
          .map(name => {
            name.has_prefix("/") &&
            paths.any(path => path.to_lower() == name[1:].to_owned().to_lower())
          })
          .unwrap_or(false)
        } else {
          node.attribute("Id").map(id => ids.contains(id)).unwrap_or(false)
        })
      })
    if !selected.is_empty() {
      let (document, edit) = original.edit_source(
        selected.iter().map(node => sheet_node_removal(tree, node)).collect(),
      )
      parts[path] = document
      edits.push((path, edit))
    }
  }
  self.commit(
    plan.sheets,
    workbook,
    plan.calculation,
    edits,
    (sheet, pivot.range),
    parts~,
    created_parts=plan.created_parts,
    removed~,
    pivot_edits=[part],
  )
  self.pivots(self.revision, sheet)
}
