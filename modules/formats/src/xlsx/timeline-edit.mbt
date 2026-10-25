///|
fn Session::affected_timeline_caches(
  self : Session,
  pivots : Array[PivotLocation],
  date_caches~ : Array[String] = [],
) -> Array[TimelineCache] raise @failure.Failure {
  let result : Array[TimelineCache] = []
  let known = self.pivot_locations()
  let mut units = 0
  for
    part in self.timeline_parts(
      self.main,
      self.workbook,
      timeline_cache_extension,
      "timelineCacheRefs",
      "timelineCacheRef",
      "TimelineCache",
    ) {
    let document = self.part_xml(part)
    let tree = Tree::new(document)
    let shared = !date_caches.is_empty() &&
      tree
      .timeline_children(0, "state")
      .any(node => {
        date_caches.contains(
          self.timeline_pivot_cache(
            node.attribute("pivotCacheId").unwrap_or(""),
          ),
        )
      })
    if !shared &&
      !tree
      .timeline_children(0, "pivotTables")
      .any(list => {
        tree
        .timeline_children(list.id, "pivotTable")
        .any(node => {
          pivots.any(pivot => {
            decode_text(node.attribute("name").unwrap_or("")) == pivot.name &&
            self.slicer_pivot_sheet(node.attribute("tabId").unwrap_or("")) ==
            pivot.sheet
          })
        })
      }) {
      continue
    }
    units += document.source().length()
    guard units <= 1048576 else {
      @failure.reject(
        "limit-exceeded", "Connected timeline metadata exceeds budget",
      )
    }
    result.push(self.read_timeline_cache(part, known))
  }
  result
}

///|
fn Session::set_timeline_selection(
  self : Session,
  cache : TimelineCache,
  range : TimelineRange?,
  edits : Array[(String, @xml.Edit)],
) -> Unit raise @failure.Failure {
  let original = self.part_xml(cache.part)
  let tree = Tree::new(original)
  let state = tree.timeline_node(0, "state")
  let changes = metadata_changes(state, [
    ("singleRangeFilterState", "1"),
    ("filterType", if range is Some(_) { "dateBetween" } else { "unknown" }),
  ])
  let selected = tree.timeline_children(state.id, "selection").get(0)
  match (selected, range) {
    (Some(node), Some(range)) =>
      changes.append(
        metadata_changes(node, [
          ("startDate", range.start),
          ("endDate", range.end),
        ]),
      )
    (Some(node), None) =>
      changes.push({
        node: state.id,
        offset: node.start - state.start,
        length: node.end - node.start,
        xml: "",
      })
    (None, Some(range)) =>
      changes.push({
        node: state.id,
        offset: tree.timeline_node(state.id, "bounds").start - state.start,
        length: 0,
        xml: "<selection xmlns='\{timeline_uri}' startDate='\{escaped_attribute(range.start)}' endDate='\{escaped_attribute(range.end)}'/>",
      })
    _ => ()
  }
  if !changes.is_empty() {
    let (document, edit) = original.edit_source(changes)
    self.parts[cache.part] = document
    edits.push((cache.part, edit))
  }
}

///|
/// Filters connected native pivot caches by an absolute date range without refreshing source data.
pub fn Session::filter_timeline(
  self : Session,
  revision : Int,
  sheet : String,
  name : String,
  range : (String, String)?,
) -> Json raise @failure.Failure {
  self.apply_timeline_filter(revision, sheet, name, range)
}

///|
fn Session::apply_timeline_filter(
  self : Session,
  revision : Int,
  sheet : String,
  name : String,
  range : (String, String)?,
  view_changes~ : Array[(String, String)] = [],
  retained~ : TimelineRange? = None,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let current = self.sheets[self.sheet_index(sheet)]
  guard self.read_only.is_empty() &&
    !current.locked &&
    current.state == "visible" else {
    @failure.reject(
      "protected-content", "Timeline worksheet is protected or hidden",
    )
  }
  guard self.read_timelines(sheet).filter(item => item.name == name)
    is [control] else {
    @failure.reject(
      "invalid-operation", "Timeline is outside the selected worksheet",
    )
  }
  let cache = control.cache
  let tree = Tree::new(self.part_xml(cache.part))
  guard !cache.connections.is_empty() &&
    cache.state.singleRange &&
    ["unknown", "dateBetween", "dateEqual"].contains(cache.state.filterType) &&
    tree.timeline_children(0, "timelinePivotFilter").is_empty() else {
    @failure.reject(
      "protected-content", "Timeline filter state requires additional support",
    )
  }
  let bounds = cache.state.bounds
  let selection = range.map(pair => {
    let start = pivot_date_parse(pair.0, false)
    let end = pivot_date_parse(pair.1, false)
    guard start <= end &&
      (
        start >= pivot_date_parse(bounds.start, false) ||
        retained.map(old => old.start == pair.0).unwrap_or(false)
      ) &&
      (
        end <= pivot_date_parse(bounds.end, false) ||
        retained.map(old => old.end == pair.1).unwrap_or(false)
      ) else {
      @failure.reject(
        "invalid-operation", "Timeline range is outside available dates or reversed",
      )
    }
    TimelineRange::{ start: pair.0, end: pair.1, }
  })
  let linked = self.timeline_filter_group(cache)
  let connections : Array[(PivotLocation, Int)] = []
  let seen : Set[(String, Int)] = Set([])
  for other in linked {
    for pair in other.connections {
      let key = (pair.0.part, pair.1)
      if !seen.contains(key) {
        seen.add(key)
        connections.push(pair)
      }
    }
  }
  let pivots = connections.map(pair => pair.0)
  let slicers = self.affected_slicer_caches(pivots)
  let candidate = { ..self, parts: self.parts.copy(), }
  let edits : Array[(String, @xml.Edit)] = []
  let created : Map[String, @xml.Document] = Map([])
  let changed : Array[String] = []
  let contexts : Map[String, (PivotSettings, PivotCache)] = Map([])
  // Update candidate ranges together before grouped calendars read their record filters.
  for other in linked {
    candidate.set_timeline_selection(other, selection, edits)
  }
  let mut work = 0
  for (pivot, field) in connections {
    let (settings, records) = candidate.cached_pivot_settings(pivot)
    guard !settings.numberGroups.any(group => group.field == field) else {
      @failure.reject(
        "protected-content", "Timeline fields cannot use numeric grouping",
      )
    }
    let data = candidate.cached_pivot(pivot, settings, records)
    let native = Tree::new(candidate.part_xml(pivot.cache))
    let definition = native.all(
        native.one(0, "cacheFields").unwrap().id,
        "cacheField",
      )[field]
    guard native.one(definition.id, "sharedItems") is Some(items) &&
      native.children
      .get(items.id)
      .unwrap_or([])
      .all(node => ["d", "m"].contains(node.name)) else {
      @failure.reject(
        "protected-content", "Timeline field requires native date or blank cache members",
      )
    }
    let selected = data.timeline_members(field, selection)
    let filters = settings.filters.filter(filter => filter.field != field)
    let report = settings.filters.any(filter => {
      filter.field == field && filter.report
    })
    if selected is Some(_) || report {
      filters.push({ field, report, values: selected, })
    }
    let settings = { ..settings, filters, }
    contexts[pivot.part] = (settings, data)
    if candidate.prepare_pivot(
        revision,
        pivot.sheet,
        pivot.part,
        Some(settings),
        cached=Some(data),
      )
      is Some((plan, range)) {
      work += (range.bottom - range.top + 1) * (range.right - range.left + 1)
      guard work <= 65536 else {
        @failure.reject(
          "limit-exceeded", "Connected timeline output exceeds budget",
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
  for slicer in slicers {
    let last = pivots
      .filter(pivot => slicer.pivots.any(other => other.part == pivot.part))
      .last()
      .unwrap()
    let (settings, data) = contexts[last.part]
    candidate.sync_slicer_state(slicer, settings, data, edits)
  }
  if !view_changes.is_empty() {
    let document = candidate.part_xml(control.part)
    let tree = Tree::new(document)
    let node = tree
      .timeline_children(0, "timeline")
      .iter()
      .find_first(node => slicer_text(node, "name") == control.name)
      .unwrap()
    let changes = metadata_changes(node, view_changes)
    if !changes.is_empty() {
      let (document, edit) = document.edit_source(changes)
      candidate.parts[control.part] = document
      edits.push((control.part, edit))
    }
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
