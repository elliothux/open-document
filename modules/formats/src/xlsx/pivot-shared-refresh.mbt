///|
// A cache refresh must replace every dependent pivot and slicer in the same transaction.
fn Session::refresh_shared_pivot(
  self : Session,
  revision : Int,
  sheet : String,
  part : String,
  replacement~ : PivotSettings? = None,
) -> Bool raise @failure.Failure {
  self.check_revision(revision)
  let known = self.pivot_locations()
  guard known
    .iter()
    .find_first(pivot => pivot.sheet == sheet && pivot.part == part)
    is Some(target) else {
    @failure.reject(
      "invalid-operation", "Pivot is outside the selected worksheet",
    )
  }
  let pivots = known.filter(pivot => pivot.cache == target.cache)
  if !self.affected_timeline_caches(pivots).is_empty() {
    self.refresh_timeline_pivots(
      revision,
      target,
      known,
      replacement=replacement.map(settings => (part, settings)),
    )
    return true
  }
  let slicers = self.affected_slicer_caches(pivots)
  if pivots.length() == 1 && slicers.is_empty() {
    return false
  }
  guard pivots.length() <= 16 else {
    @failure.reject(
      "limit-exceeded", "Shared pivot refresh exceeds connection budget",
    )
  }
  let contexts = pivots.map(pivot => self.pivot_settings(pivot, shared=true))
  let old = Tree::new(self.part_xml(target.cache))
  let fields = old
    .all(old.one(0, "cacheFields").unwrap().id, "cacheField")
    .map(node => decode_text(node.attribute("name").unwrap_or("")))
  if replacement is Some(next) {
    ignore(next.validate())
    guard next.values.all(value => {
      !fields.any(field => field.to_lower() == value.name.to_lower())
    }) else {
      @failure.reject(
        "invalid-operation", "Pivot value captions must differ from native source field names",
      )
    }
    let index = pivots.search_by(pivot => pivot.part == part).unwrap()
    let previous = contexts[index].0
    guard Json(next.numberGroups) == Json(previous.numberGroups) &&
      Json(next.dateGroups) == Json(previous.dateGroups) else {
      @failure.reject(
        "protected-content", "Linked grouping changes require field mapping",
      )
    }
    guard next.filters.all(filter => {
      filter.report ||
      filter.values is None ||
      (next.rows + next.columns).contains(filter.field) ||
      slicers.any(cache => {
        cache.field == filter.field &&
        cache.pivots.any(pivot => pivot.part == part)
      })
    }) else {
      @failure.reject(
        "protected-content", "Unused pivot member filters require a linked slicer",
      )
    }
    for peer, context in contexts {
      contexts[peer] = (
        { ..context.0, sourceSheet: next.sourceSheet, source: next.source, },
        context.1,
      )
    }
    contexts[index] = (next, contexts[index].1)
  }
  let settings = contexts[0].0
  guard contexts.all(context => {
    let other = context.0
    other.sourceSheet == settings.sourceSheet &&
    other.source == settings.source &&
    Json(other.numberGroups) == Json(settings.numberGroups) &&
    Json(other.dateGroups) == Json(settings.dateGroups) &&
    context.1 == contexts[0].1
  }) else {
    @failure.reject(
      "protected-content", "Shared pivot source or grouping is inconsistent",
    )
  }
  let data = self.pivot_cache(
    settings,
    peers=contexts[1:].map(context => context.0),
  )
  guard fields == data.headers else {
    @failure.reject(
      "protected-content", "Pivot source headers changed; field remapping is required",
    )
  }
  let candidate = { ..self, parts: self.parts.copy(), }
  let edits : Array[(String, @xml.Edit)] = []
  let created : Map[String, @xml.Document] = Map([])
  let changed : Array[String] = []
  let mut work = 0
  for index, pivot in pivots {
    let next = candidate.prepare_pivot(
      revision,
      pivot.sheet,
      pivot.part,
      Some(contexts[index].0),
      cached=Some(data),
    )
    if next is Some((plan, range)) {
      work += (range.bottom - range.top + 1) * (range.right - range.left + 1)
      guard work <= 65536 else {
        @failure.reject("limit-exceeded", "Shared pivot output exceeds budget")
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
  let records = contexts[0].1
  let relation = self
    .relationships()
    .iter()
    .find_first(link => link.owner == target.cache && link.target == records)
    .unwrap().id
  for
    (path, markup) in [
      (
        target.cache,
        data.definition(
          self.sheets[self.sheet_index(settings.sourceSheet)].name,
          settings.source,
          relation,
        ),
      ),
      (records, data.record_markup()),
    ] {
    let original = self.part_xml(path)
    if original.source() != markup {
      let (document, edit) = pivot_root_edit(original, markup)
      candidate.parts[path] = document
      edits.push((path, edit))
    }
  }
  for cache in slicers {
    let last = cache.pivots.last().unwrap()
    let index = pivots.search_by(pivot => pivot.part == last.part).unwrap()
    candidate.rebuild_slicer_state(cache, contexts[index].0, data, edits)
  }
  ignore(
    candidate.affected_slicer_caches(
      candidate.pivot_locations().filter(pivot => pivot.cache == target.cache),
    ),
  )
  if !edits.is_empty() {
    self.commit(
      candidate.sheets,
      self.workbook,
      candidate.calculation.unwrap(),
      edits,
      self.selection,
      parts=candidate.parts,
      created_parts=created,
      pivot_edits=changed,
    )
  }
  true
}
