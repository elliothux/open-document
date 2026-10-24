///|
/// Removes a native pivot, disconnects analysis controls and clears its owned output in one history entry.
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
  let timelines = self.affected_timeline_caches([pivot])
  let related = self.deletion_slicer_caches(pivot)
  let shared = self
    .pivot_locations()
    .any(other => other.part != part && other.cache == pivot.cache)
  guard !current.merges.any(range => range.intersects(pivot.range)) &&
    !self
    .table_definitions(self.sheets, self.workbook, self.parts)
    .any(table => table.sheet == sheet && table.range.intersects(pivot.range)) else {
    @failure.reject(
      "protected-content", "Pivot output overlaps a merged or structured range",
    )
  }
  let links = self.relationships()
  let (owned, paths) = self.pivot_deletion_parts([pivot])
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
  let rule_tree = Tree::new(plan.sheets[index].document)
  let slicer_metadata = rule_tree
    .one(rule_tree.root("worksheet").id, "extLst")
    .map(node => {
      self.timeline_extension(plan.sheets[index], rule_tree, node) ||
      (
        self.slicer_extension(plan.sheets[index], rule_tree, node) &&
        rule_tree
        .all(node.id, "ext")
        .all(entry => {
          entry
          .attribute("uri")
          .map(uri => uri.to_upper() == slicer_list_extension)
          .unwrap_or(false)
        })
      )
    })
    .unwrap_or(false)
  let changes = clear_rules(
    plan.sheets[index].document,
    pivot.range,
    true,
    table_parts=true,
    slicer_metadata~,
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
  let removed : Map[String, @xml.Document] = Map([])
  let candidate = {
    ..self,
    removed: self.removed.copy(),
    sheets: plan.sheets,
    parts,
    styles: plan.styles,
    calculation: Some(plan.calculation),
  }
  candidate.remove_pivot_slicers(pivot, related, edits, removed)
  candidate.remove_pivot_timelines(pivot, timelines, edits, removed)
  if !shared {
    let (workbook, edit) = candidate.remove_pivot_cache_reference(pivot)
    candidate.workbook = workbook
    edits.push((self.main, edit))
  }
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
    candidate.sheets,
    candidate.workbook,
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
