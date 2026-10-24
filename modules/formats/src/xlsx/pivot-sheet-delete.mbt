///|
fn Session::prepare_pivot_sheet_delete(
  self : Session,
  sheet : String,
  parts : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
  workbook_changes : Array[@xml.SourceChange],
  pivot_edits : Array[String],
  profiles~ : Session? = None,
) -> Array[String] raise @failure.Failure {
  let known = self.pivot_locations()
  let selected = known.filter(p => p.sheet == sheet)
  let (_, paths) = self.pivot_deletion_parts(selected, profiles~)
  let caches = selected.filter(p => {
    !known.any(peer => peer.cache == p.cache && peer.sheet != sheet)
  })
  if !caches.is_empty() {
    workbook_changes.append(self.pivot_cache_removals(caches))
  }
  pivot_edits.append(selected.map(p => p.part))
  for pivot in known {
    if pivot.sheet != sheet && pivot.sourceSheet == Some(sheet) {
      ignore(profiles.unwrap_or(self).cached_pivot_settings(pivot))
      pivot_edits.push(pivot.part)
    }
  }
  let deleted = self.sheets[self.sheet_index(sheet)].name
  let seen : Set[String] = Set([])
  for link in self.relationships() {
    if link.owner == self.main &&
      link.kind == relationship_uri + "pivotCacheDefinition" &&
      !link.external &&
      !paths.contains(link.target) &&
      !seen.contains(link.target) {
      seen.add(link.target)
      let original = parts
        .get(link.target)
        .unwrap_or_else(() => self.part_xml(link.target))
      let tree = Tree::new(original)
      if !tree
        .one(0, "cacheSource")
        .bind(node => tree.one(node.id, "worksheetSource"))
        .map(node => node.attribute("sheet") == Some(deleted))
        .unwrap_or(false) {
        continue
      }
      let changes = metadata_changes(original.nodes()[0], [("invalid", "1")])
      if !changes.is_empty() {
        let (document, edit) = original.edit_source(changes)
        parts[link.target] = document
        edits.push((link.target, edit))
      }
    }
  }
  paths
}
