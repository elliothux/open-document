///|
fn Session::pivot_deletion_parts(
  self : Session,
  selected : Array[PivotLocation],
  profiles~ : Session? = None,
) -> (Array[String], Array[String]) raise @failure.Failure {
  let known = self.pivot_locations()
  let records : Map[String, String] = Map([])
  let owned = selected.map(pivot => pivot.part)
  for pivot in selected {
    let (_, data) = profiles.unwrap_or(self).cached_pivot_settings(pivot)
    if !known.any(peer => {
        peer.cache == pivot.cache && !owned.contains(peer.part)
      }) &&
      !records.contains(pivot.cache) {
      records[pivot.cache] = data
    }
  }
  for cache, data in records {
    owned.append([cache, data])
  }
  let paths = owned.copy()
  for owner in owned {
    let path = workbook_relations(owner)
    if self.parts.contains(path) || self.opc.names.contains(path.to_lower()) {
      paths.push(self.opc.names.get(path.to_lower()).unwrap_or(path))
    }
  }
  for link in self.relationships() {
    if owned.contains(link.owner) {
      guard !link.external &&
        (
          selected.any(p => {
            p.part == link.owner &&
            p.cache == link.target &&
            link.kind == relationship_uri + "pivotCacheDefinition"
          }) ||
          (
            records.get(link.owner) == Some(link.target) &&
            link.kind == relationship_uri + "pivotCacheRecords"
          )
        ) else {
        @failure.reject(
          "protected-content", "Unknown outgoing pivot resource requires deletion support",
        )
      }
    } else if !link.external && paths.contains(link.target) {
      guard selected.any(p => {
          p.sheet == link.owner &&
          p.part == link.target &&
          link.kind == relationship_uri + "pivotTable"
        }) ||
        (
          link.owner == self.main &&
          records.contains(link.target) &&
          link.kind == relationship_uri + "pivotCacheDefinition"
        ) else {
        @failure.reject(
          "protected-content", "Shared or linked pivot resources require coordinated deletion",
        )
      }
    }
  }
  (owned, paths)
}
