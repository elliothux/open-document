///|
fn Session::deletion_slicer_caches(
  self : Session,
  pivot : PivotLocation,
) -> Array[SlicerCache] raise @failure.Failure {
  let known = self.pivot_locations()
  let result : Array[SlicerCache] = []
  let mut members = 0
  let mut units = 0
  for
    path in self.slicer_parts(
      self.main,
      self.workbook,
      slicer_cache_extension,
      "slicerCaches",
      "slicerCache",
      "slicerCache",
    ) {
    let tree = Tree::new(self.part_xml(path))
    let root = tree.document.nodes()[0]
    let connection = tree
      .slicer_children(root.id, "pivotTables")
      .any(list => {
        tree
        .slicer_children(list.id, "pivotTable")
        .any(node => {
          node.attribute("name").map(decode_text) == Some(pivot.name) &&
          self.slicer_pivot_sheet(node.attribute("tabId").unwrap_or("")) ==
          pivot.sheet
        })
      })
    let source = tree
      .slicer_children(root.id, "data")
      .any(data => {
        tree
        .slicer_children(data.id, "tabular")
        .any(node => {
          self.slicer_pivot_cache(node.attribute("pivotCacheId").unwrap_or("")) ==
          pivot.cache
        })
      })
    if connection || source {
      let cache = self.read_slicer_cache(path, known)
      members += cache.members.length()
      units += cache.source_units
      guard members <= 16384 && units <= 1048576 else {
        @failure.reject(
          "limit-exceeded", "Connected slicer deletion exceeds member budget",
        )
      }
      result.push(cache)
    }
  }
  result
}

///|
fn Session::remove_pivot_slicers(
  self : Session,
  pivot : PivotLocation,
  caches : Array[SlicerCache],
  edits : Array[(String, @xml.Edit)],
  removed : Map[String, @xml.Document],
) -> Unit raise @failure.Failure {
  let dead = caches.filter(cache => {
    cache.pivots.length() == 1 && cache.pivots[0].part == pivot.part
  })
  let wanted = dead.map(cache => cache.name)
  let views : Array[(String, String)] = []
  if !dead.is_empty() {
    // Inspect only native view identities here; unrelated unsupported caches remain opaque.
    for sheet in self.sheets {
      for
        path in self.slicer_parts(
          sheet.id,
          sheet.document,
          slicer_list_extension,
          "slicerList",
          "slicer",
          "slicer",
        ) {
        let tree = Tree::new(self.part_xml(path))
        for node in tree.slicer_children(tree.document.nodes()[0].id, "slicer") {
          if wanted.contains(slicer_text(node, "cache")) {
            guard views.length() < 256 else {
              @failure.reject(
                "limit-exceeded", "Connected slicer deletion exceeds view budget",
              )
            }
            views.push((sheet.id, slicer_text(node, "name")))
          }
        }
      }
    }
  }
  for (sheet, name) in views {
    self.remove_analysis_view(sheet, name, edits, removed)
  }
  for cache in caches {
    let remaining = cache.pivots.filter(other => other.part != pivot.part)
    if remaining.length() == cache.pivots.length() {
      continue
    }
    if remaining.is_empty() {
      let links = self.relationships()
      guard links.filter(link => !link.external && link.target == cache.part)
        is [link] &&
        link.owner == self.main &&
        link.kind == slicer_relationship_uri + "slicerCache" &&
        !links.any(link => link.owner == cache.part) else {
        @failure.reject(
          "protected-content", "Shared or extended slicer cache resources require deletion support",
        )
      }
      let (workbook, edit) = remove_analysis_reference(
        self.workbook,
        slicer_cache_extension,
        "slicerCaches",
        "slicerCache",
        link.id,
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
      let connections = tree.slicer_node(document.nodes()[0].id, "pivotTables")
      let matches = tree
        .slicer_children(connections.id, "pivotTable")
        .filter(node => {
          node.attribute("name").map(decode_text) == Some(pivot.name) &&
          self.slicer_pivot_sheet(node.attribute("tabId").unwrap_or("")) ==
          pivot.sheet
        })
      guard matches is [node] else {
        @failure.reject(
          "protected-content", "Slicer pivot deletion requires an unambiguous connection",
        )
      }
      let (document, edit) = document.edit_source([
        sheet_node_removal(tree, node),
      ])
      self.parts[cache.part] = document
      edits.push((cache.part, edit))
      let last = remaining.last().unwrap()
      let (settings, records) = self.pivot_settings(last, shared=true)
      self.sync_slicer_state(
        { ..cache, pivots: remaining, },
        settings,
        self.cached_pivot(last, settings, records),
        edits,
      )
    }
  }
}
