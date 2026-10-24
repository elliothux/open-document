///|
fn Session::remove_pivot_timelines(
  self : Session,
  pivot : PivotLocation,
  caches : Array[TimelineCache],
  edits : Array[(String, @xml.Edit)],
  removed : Map[String, @xml.Document],
  deleted_sheet~ : String? = None,
) -> Unit raise @failure.Failure {
  if caches.is_empty() {
    return
  }
  let dead = caches.filter(cache => {
    cache.connections is [(only, _)] && only.part == pivot.part
  })
  let wanted = dead.map(cache => cache.name.to_lower())
  let views : Array[(String, String)] = []
  let mut units = 0
  if !dead.is_empty() {
    for sheet in self.sheets {
      if deleted_sheet == Some(sheet.id) {
        continue
      }
      for
        part in self.timeline_parts(
          sheet.id,
          sheet.document,
          timeline_view_extension,
          "timelineRefs",
          "timelineRef",
          "Timeline",
        ) {
        let document = self.part_xml(part)
        units += document.source().length()
        guard units <= 1048576 else {
          @failure.reject(
            "limit-exceeded", "Connected timeline deletion exceeds source budget",
          )
        }
        let tree = Tree::new(document)
        for node in tree.timeline_children(0, "timeline") {
          if wanted.contains(slicer_text(node, "cache").to_lower()) {
            guard views.length() < 256 else {
              @failure.reject(
                "limit-exceeded", "Connected timeline deletion exceeds view budget",
              )
            }
            views.push((sheet.id, slicer_text(node, "name")))
          }
        }
      }
    }
  }
  for (sheet, name) in views {
    self.remove_analysis_view(sheet, name, edits, removed, timeline=true)
  }
  for cache in caches {
    let remaining = cache.connections.filter(pair => pair.0.part != pivot.part)
    if remaining.is_empty() {
      let links = self.relationships()
      guard links.filter(link => !link.external && link.target == cache.part)
        is [link] &&
        link.owner == self.main &&
        link.kind == timeline_relationship_uri + "TimelineCache" &&
        !links.any(link => link.owner == cache.part) else {
        @failure.reject(
          "protected-content", "Shared or extended timeline cache requires deletion support",
        )
      }
      let (workbook, edit) = remove_analysis_reference(
        self.workbook,
        timeline_cache_extension,
        "timelineCacheRefs",
        "timelineCacheRef",
        link.id,
        payload_uri=timeline_uri,
      )
      self.workbook = workbook
      edits.push((self.main, edit))
      self.detach_analysis_resource(
        self.main,
        cache.part,
        link.id,
        self.parts,
        removed,
        edits,
      )
    } else {
      let document = self.part_xml(cache.part)
      let tree = Tree::new(document)
      let list = tree.timeline_node(0, "pivotTables")
      guard tree
        .timeline_children(list.id, "pivotTable")
        .filter(node => {
          slicer_text(node, "name") == pivot.name &&
          self.slicer_pivot_sheet(node.attribute("tabId").unwrap_or("")) ==
          pivot.sheet
        })
        is [entry] else {
        @failure.reject(
          "protected-content", "Timeline deletion requires an unambiguous pivot connection",
        )
      }
      let (document, edit) = document.edit_source([
        sheet_node_removal(tree, entry),
      ])
      self.parts[cache.part] = document
      edits.push((cache.part, edit))
    }
  }
  if dead.is_empty() {
    return
  }
  let retained = self
    .timeline_parts(
      self.main,
      self.workbook,
      timeline_cache_extension,
      "timelineCacheRefs",
      "timelineCacheRef",
      "TimelineCache",
    )
    .map(part => {
      let document = self.part_xml(part)
      units += document.source().length()
      guard units <= 1048576 else {
        @failure.reject(
          "limit-exceeded", "Connected timeline deletion exceeds source budget",
        )
      }
      let tree = Tree::new(document)
      self.timeline_pivot_cache(
        tree.timeline_node(0, "state").attribute("pivotCacheId").unwrap_or(""),
      )
    })
  let cleaned : Map[String, Bool] = Map([])
  for cache in dead {
    if !retained.contains(cache.pivot_cache) &&
      !cleaned.contains(cache.pivot_cache) {
      self.remove_timeline_data_cache(cache.pivot_cache, edits, removed)
      cleaned[cache.pivot_cache] = true
    }
  }
}
