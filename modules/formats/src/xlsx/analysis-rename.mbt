///|
fn Session::analysis_workbook_extension(
  self : Session,
  tree : Tree,
  list : @xml.Node,
) -> Bool raise @failure.Failure {
  if !list.attributes.is_empty() || !list.text.trim().is_empty() {
    return false
  }
  for ext in tree.children.get(list.id).unwrap_or([]) {
    if ext.uri != spreadsheet_uri ||
      ext.name != "ext" ||
      ext.attributes.length() != 1 ||
      !ext.text.trim().is_empty() {
      return false
    }
    match ext.attribute("uri").unwrap_or("").to_upper() {
      uri if uri == slicer_cache_extension =>
        ignore(
          self.slicer_parts(
            self.main,
            self.workbook,
            uri,
            "slicerCaches",
            "slicerCache",
            "slicerCache",
          ),
        )
      uri if uri == timeline_cache_extension =>
        ignore(
          self.timeline_parts(
            self.main,
            self.workbook,
            uri,
            "timelineCacheRefs",
            "timelineCacheRef",
            "TimelineCache",
          ),
        )
      "{A2CB5862-8E78-49C6-8D9D-AF26E26ADB89}" => {
        guard tree.children.get(ext.id).unwrap_or([]) is [directory] &&
          directory.uri == timeline_uri &&
          directory.name == "timelineCachePivotCaches" &&
          directory.attributes.is_empty() &&
          directory.text.trim().is_empty() else {
          return false
        }
        let caches = tree.children.get(directory.id).unwrap_or([])
        guard !caches.is_empty() && caches.length() <= 64 else { return false }
        for cache in caches {
          guard cache.uri == spreadsheet_uri &&
            cache.name == "pivotCache" &&
            cache.attributes.length() == 2 &&
            cache.text.trim().is_empty() &&
            tree.children.get(cache.id).unwrap_or([]).is_empty() else {
            return false
          }
          ignore(
            self.timeline_pivot_cache(cache.attribute("cacheId").unwrap_or("")),
          )
        }
      }
      _ => return false
    }
  }
  true
}

///|
// Renaming keeps cache records and stable tabId connections, including pending source edits.
fn Session::analysis_rename_parts(
  self : Session,
) -> Array[String] raise @failure.Failure {
  let parts : Set[String] = Set([])
  let pivots = self.pivot_locations()
  for pivot in pivots {
    ignore(self.pivot_settings(pivot, shared=true))
    parts.add(pivot.part)
    parts.add(pivot.cache)
  }
  let caches = self.slicer_parts(
    self.main,
    self.workbook,
    slicer_cache_extension,
    "slicerCaches",
    "slicerCache",
    "slicerCache",
  )
  ignore(
    self.slicer_caches(
      caches.map(path => slicer_text(self.part_xml(path).nodes()[0], "name")),
    ),
  )
  for part in caches {
    parts.add(part)
  }
  for
    part in self.timeline_parts(
      self.main,
      self.workbook,
      timeline_cache_extension,
      "timelineCacheRefs",
      "timelineCacheRef",
      "TimelineCache",
    ) {
    let cache = self.read_timeline_cache(part, pivots)
    parts.add(part)
    parts.add(cache.pivot_cache)
  }
  let workbook = Tree::new(self.workbook)
  for
    entry in workbook
    .one(0, "pivotCaches")
    .map(node => workbook.all(node.id, "pivotCache"))
    .unwrap_or([]) {
    let path = self.slicer_pivot_cache(entry.attribute("cacheId").unwrap_or(""))
    if !parts.contains(path) {
      guard self.relationships().filter(link => link.owner == path) is [records] &&
        !records.external &&
        records.kind == relationship_uri + "pivotCacheRecords" else {
        @failure.reject(
          "protected-content", "Unknown unused pivot cache resources prevent renaming",
        )
      }
      pivot_cache_profile(self.part_xml(path), records.id)
      parts.add(path)
    }
  }
  for sheet in self.sheets {
    ignore(self.read_slicers(sheet.id))
    ignore(self.read_timelines(sheet.id))
    for
      path in self.slicer_parts(
        sheet.id,
        sheet.document,
        slicer_list_extension,
        "slicerList",
        "slicer",
        "slicer",
      ) {
      parts.add(path)
    }
    for
      path in self.timeline_parts(
        sheet.id,
        sheet.document,
        timeline_view_extension,
        "timelineRefs",
        "timelineRef",
        "Timeline",
      ) {
      parts.add(path)
    }
  }
  parts.to_array()
}

///|
fn Session::rename_analysis_sources(
  self : Session,
  old : String,
  name : String,
  parts : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
) -> Unit raise @failure.Failure {
  for path in self.analysis_rename_parts() {
    let document = self.part_xml(path)
    if document.nodes()[0].name != "pivotCacheDefinition" {
      continue
    }
    let tree = Tree::new(document)
    let source = tree
      .one(0, "cacheSource")
      .bind(node => tree.one(node.id, "worksheetSource"))
    guard source is Some(source) &&
      source
      .attribute("sheet")
      .map(value => value.to_lower() == old.to_lower())
      .unwrap_or(false) else {
      continue
    }
    let (document, edit) = document.edit_source(
      metadata_changes(source, [("sheet", name)]),
    )
    parts[path] = document
    edits.push((path, edit))
  }
}
