///|
fn Session::protect_slicer_cache(
  self : Session,
  sheet : String,
  part : String,
) -> Unit raise @failure.Failure {
  let pivot = self
    .pivot_locations()
    .iter()
    .find_first(p => p.sheet == sheet && p.part == part)
  guard pivot is Some(pivot) else { return }
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
    if tree
      .slicer_children(root.id, "pivotTables")
      .any(list => {
        tree
        .slicer_children(list.id, "pivotTable")
        .any(node => {
          node.attribute("name") == Some(pivot.name) &&
          self.slicer_pivot_sheet(node.attribute("tabId").unwrap_or("")) ==
          sheet
        })
      }) {
      @failure.reject(
        "protected-content", "Linked slicers require coordinated pivot editing",
      )
    }
    if tree
      .slicer_children(root.id, "data")
      .any(data => {
        tree
        .slicer_children(data.id, "tabular")
        .any(node => {
          self.slicer_pivot_cache(node.attribute("pivotCacheId").unwrap_or("")) ==
          pivot.cache
        })
      }) {
      @failure.reject(
        "protected-content", "Linked slicer cache requires coordinated refresh",
      )
    }
  }
}

///|
/// Applies native cache member indices to connected pivots in one history entry.
pub fn Session::filter_slicer(
  self : Session,
  revision : Int,
  sheet : String,
  name : String,
  indices : Array[Int],
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let current = self.sheets[self.sheet_index(sheet)]
  guard !current.locked &&
    current.state == "visible" &&
    self.read_only.is_empty() else {
    @failure.reject(
      "protected-content", "Slicer worksheet is protected or hidden",
    )
  }
  guard !indices.is_empty() && indices.length() <= 4096 else {
    @failure.reject("invalid-operation", "Select one or more slicer members")
  }
  guard self
    .read_slicers(sheet)
    .iter()
    .find_first(control => control.name == name)
    is Some(control) else {
    @failure.reject(
      "invalid-operation", "Slicer is outside the selected worksheet",
    )
  }
  let cache = control.cache
  guard !self
    .affected_timeline_caches(cache.pivots)
    .any(timeline => {
      timeline.connections.any(pair => {
        pair.1 == cache.field &&
        cache.pivots.any(pivot => pivot.part == pair.0.part)
      })
    }) else {
    @failure.reject(
      "protected-content", "Use the linked timeline to filter this date field",
    )
  }
  let selected : Map[Int, Bool] = Map([])
  let members = Map::from_array(cache.members.map(item => (item.index, true)))
  for index in indices {
    guard !selected.contains(index) && members.contains(index) else {
      @failure.reject("invalid-operation", "Invalid or duplicate slicer member")
    }
    selected[index] = true
  }
  let values = cache.members
    .filter(item => selected.contains(item.index))
    .map(item => item.value)
  let candidate : Session = { ..self, parts: self.parts.copy(), }
  let edits : Array[(String, @xml.Edit)] = []
  let created : Map[String, @xml.Document] = Map([])
  let changed : Array[String] = []
  let contexts : Map[String, (PivotSettings, PivotCache)] = Map([])
  let related = self.affected_slicer_caches(cache.pivots)
  let mut work = 0
  for pivot in cache.pivots {
    let (settings, records) = candidate.pivot_settings(pivot, shared=true)
    guard cache.field < settings.validate().right - settings.validate().left + 1 else {
      @failure.reject(
        "protected-content", "Slicer source field is outside the source range",
      )
    }
    let data = candidate.cached_pivot(pivot, settings, records)
    guard cache.members.length() == data.axis_items(cache.field).length() else {
      @failure.reject(
        "protected-content", "Slicer cache does not enumerate every pivot member",
      )
    }
    let filters = settings.filters.filter(filter => filter.field != cache.field)
    let report = settings.filters.any(filter => {
      filter.field == cache.field && filter.report
    })
    if report || values.length() != data.axis_items(cache.field).length() {
      filters.push({
        field: cache.field,
        report,
        values: if selected.length() == cache.members.length() {
          None
        } else {
          Some(values)
        },
      })
    }
    let settings = { ..settings, filters, }
    contexts[pivot.part] = (settings, data)
    let next = candidate.prepare_pivot(
      revision,
      pivot.sheet,
      pivot.part,
      Some(settings),
      cached=Some(data),
    )
    if next is Some((plan, range)) {
      work += (range.bottom - range.top + 1) * (range.right - range.left + 1)
      guard work <= 65536 else {
        @failure.reject(
          "limit-exceeded", "Connected pivot output exceeds budget",
        )
      }
      candidate.sheets = plan.sheets
      candidate.parts = plan.parts
      candidate.styles = plan.styles
      candidate.calculation = Some(plan.calculation)
      edits.append(plan.edits)
      for path, document in plan.created_parts {
        created[path] = document
      }
      changed.push(pivot.part)
    }
  }
  for linked in related {
    let last = cache.pivots
      .filter(pivot => linked.pivots.any(other => other.part == pivot.part))
      .last()
      .unwrap()
    let (settings, data) = contexts[last.part]
    candidate.sync_slicer_state(linked, settings, data, edits)
  }
  if !edits.is_empty() {
    self.commit(
      candidate.sheets,
      self.workbook,
      candidate.calculation.unwrap_or_else(() => {
        candidate.calculate(
          candidate.sheets,
          candidate.calculation,
          [],
          self.workbook,
        )
      }),
      edits,
      self.selection,
      parts=candidate.parts,
      created_parts=created,
      pivot_edits=changed,
    )
  }
  self.query()
}
