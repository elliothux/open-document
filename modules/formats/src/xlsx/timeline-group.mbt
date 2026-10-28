///|
// Calendar labels can span several source dates; the native timeline range filters records first.
fn Session::timeline_filtered_cache(
  self : Session,
  pivot : PivotLocation,
  data : PivotCache,
) -> PivotCache raise @failure.Failure {
  if !data.groups.values().any(group => group.settings is DateBuckets(_, ..)) {
    return data
  }
  let filters : Array[(Int32, Map[Int32, Bool])] = []
  let seen : Map[Int32, TimelineState] = Map([])
  for cache in self.affected_timeline_caches([pivot]) {
    for (target, _) in cache.connections {
      if target.part != pivot.part {
        continue
      }
      let field = pivot_source_field(data.headers, cache.source)
      guard field < data.source_width else {
        @failure.reject(
          "protected-content", "Timeline must target an original date column",
        )
      }
      if !data.groups.contains(field) {
        continue
      }
      guard data.groups[field].settings is DateBuckets(_, ..) &&
        cache.state.singleRange &&
        ["unknown", "dateBetween", "dateEqual"].contains(cache.state.filterType) &&
        Tree::new(self.part_xml(cache.part))
        .timeline_children(0, "timelinePivotFilter")
        .is_empty() else {
        @failure.reject(
          "protected-content", "Timeline calendar source filter requires a unique continuous range",
        )
      }
      if seen.get(field) is Some(previous) {
        guard previous.same_filter(cache.state) else {
          @failure.reject(
            "protected-content", "Overlapping timeline selections disagree",
          )
        }
        continue
      }
      seen[field] = cache.state
      let range = cache.state.selection
      if range is Some(range) {
        let start = pivot_date_parse(range.start, self.date1904)
        let end = pivot_date_parse(range.end, self.date1904)
        let selected : Map[Int32, Bool] = Map([])
        for index, value in data.items[field] {
          if value is Number(date) && date >= start && date <= end {
            selected[index] = true
          }
        }
        filters.push((field, selected))
      } else if cache.state.filterType != "unknown" {
        filters.push((field, Map([])))
      }
    }
  }
  { ..data, source_filters: filters, }
}

///|
fn PivotCache::timeline_members(
  self : PivotCache,
  field : Int32,
  range : TimelineRange?,
) -> Array[Value]? raise @failure.Failure {
  range.map(range => {
    let start = pivot_date_parse(range.start, self.date1904)
    let end = pivot_date_parse(range.end, self.date1904)
    let selected : Map[Int32, Bool] = Map([])
    for index, value in self.items[field] {
      if value is Number(date) && date >= start && date <= end {
        selected[self.groups
        .get(field)
        .map(group => group.indices[index])
        .unwrap_or(index)] = true
      }
    }
    self
    .axis_items(field)
    .mapi((index, value) => {
      if selected.contains(index) {
        Some(value)
      } else {
        None
      }
    })
    .filter_map(value => value)
  })
}
