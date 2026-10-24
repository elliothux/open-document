///|
fn Session::refresh_timeline_pivots(
  self : Session,
  revision : Int,
  target : PivotLocation,
  known : Array[PivotLocation],
  replacement~ : (String, PivotSettings)? = None,
) -> Unit raise @failure.Failure {
  guard self.read_only.is_empty() else {
    @failure.reject("protected-content", self.read_only)
  }
  let mut pivots = known.filter(pivot => pivot.cache == target.cache)
  let mut timelines = self.affected_timeline_caches(pivots)
  for ;; {
    let linked = self.affected_timeline_caches(
      pivots,
      date_caches=timelines.map(cache => cache.pivot_cache),
    )
    let next = known.filter(pivot => {
      pivots.any(peer => peer.cache == pivot.cache) ||
      linked.any(cache => {
        cache.connections.any(pair => pair.0.cache == pivot.cache)
      })
    })
    guard next.length() <= 16 else {
      @failure.reject(
        "limit-exceeded", "Timeline refresh exceeds 16 connected pivots",
      )
    }
    if next.length() == pivots.length() && linked.length() == timelines.length() {
      timelines = linked
      break
    }
    pivots = next
    timelines = linked
    continue
  }
  let fields : Map[(String, Int), String] = Map([])
  for cache in timelines {
    let tree = Tree::new(self.part_xml(cache.part))
    guard cache.state.singleRange &&
      ["unknown", "dateBetween", "dateEqual"].contains(cache.state.filterType) &&
      tree.timeline_children(0, "timelinePivotFilter").is_empty() else {
      @failure.reject(
        "protected-content", "Timeline refresh requires a continuous native date range",
      )
    }
    for (pivot, field) in cache.connections {
      guard !fields.contains((pivot.part, field)) else {
        @failure.reject(
          "protected-content", "Multiple timeline caches target the same pivot date field",
        )
      }
      fields[(pivot.part, field)] = cache.part
    }
  }
  let models : Map[String, PivotCache] = Map([])
  let contexts : Map[String, PivotSettings] = Map([])
  let records : Map[String, String] = Map([])
  for pivot in pivots {
    if !models.contains(pivot.cache) {
      let group = pivots.filter(peer => peer.cache == pivot.cache)
      let (data, settings, record) = self.timeline_refresh_group(
        group,
        timelines,
        replacement~,
      )
      models[pivot.cache] = data
      records[pivot.cache] = record
      for index, peer in group {
        contexts[peer.part] = settings[index]
      }
    }
  }
  // Resolve date conditions while result and independent cache sources still agree.
  let filtered = Map::from_array(
    pivots.map(pivot => {
      (pivot.part, self.timeline_filtered_cache(pivot, models[pivot.cache]))
    }),
  )
  let candidate = { ..self, parts: self.parts.copy(), }
  let edits : Array[(String, @xml.Edit)] = []
  let created : Map[String, @xml.Document] = Map([])
  let changed : Array[String] = []
  let mut work = 0
  for pivot in pivots {
    if candidate.prepare_pivot(
        revision,
        pivot.sheet,
        pivot.part,
        Some(contexts[pivot.part]),
        cached=Some(filtered[pivot.part]),
      )
      is Some((plan, range)) {
      work += (range.bottom - range.top + 1) * (range.right - range.left + 1)
      guard work <= 65536 else {
        @failure.reject(
          "limit-exceeded", "Timeline refresh output exceeds budget",
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
  for part, data in models {
    let pivot = pivots.iter().find_first(pivot => pivot.cache == part).unwrap()
    let settings = contexts[pivot.part]
    let record = records[part]
    let relation = self
      .relationships()
      .iter()
      .find_first(link => link.owner == part && link.target == record)
      .unwrap().id
    candidate.refresh_timeline_part(
      part,
      data.definition(
        self.sheets[self.sheet_index(settings.sourceSheet)].name,
        settings.source,
        relation,
      ),
      edits,
    )
    candidate.refresh_timeline_part(record, data.record_markup(), edits)
  }
  for cache in self.affected_slicer_caches(pivots) {
    let last = cache.pivots.last().unwrap()
    candidate.rebuild_slicer_state(
      cache,
      contexts[last.part],
      filtered[last.part],
      edits,
    )
  }
  let updated : Map[String, Bool] = Map([])
  for cache in timelines {
    let pivot = cache.connections
      .get(0)
      .map(pair => pair.0)
      .unwrap_or_else(() => {
        timelines
        .iter()
        .find_first(other => {
          other.pivot_cache == cache.pivot_cache &&
          !other.connections.is_empty()
        })
        .unwrap().connections[0].0
      })
    let data = models[pivot.cache]
    let field = data.headers.search_by(name => name == cache.source).unwrap()
    if !updated.contains(cache.pivot_cache) {
      let selected = data.native_dates +
        timelines
        .filter(other => other.pivot_cache == cache.pivot_cache)
        .map(other => other.field)
      candidate.refresh_timeline_data(
        cache,
        { ..data, native_dates: selected, },
        contexts[pivot.part],
        edits,
      )
      updated[cache.pivot_cache] = true
    }
    let bounds = data.timeline_bounds(field)
    let original = candidate.part_xml(cache.part)
    let tree = Tree::new(original)
    let changes = metadata_changes(
      tree.timeline_node(tree.timeline_node(0, "state").id, "bounds"),
      [("startDate", bounds.start), ("endDate", bounds.end)],
    )
    if !changes.is_empty() {
      let (document, edit) = original.edit_source(changes)
      candidate.parts[cache.part] = document
      edits.push((cache.part, edit))
    }
  }
  ignore(
    candidate.affected_timeline_caches(
      candidate.pivot_locations().filter(pivot => models.contains(pivot.cache)),
    ),
  )
  ignore(candidate.affected_slicer_caches(pivots))
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
}

///|
fn Session::timeline_refresh_group(
  self : Session,
  pivots : Array[PivotLocation],
  timelines : Array[TimelineCache],
  replacement~ : (String, PivotSettings)? = None,
) -> (PivotCache, Array[PivotSettings], String) raise @failure.Failure {
  let contexts = pivots.map(pivot => self.pivot_settings(pivot, shared=true))
  let original_range = contexts[0].0.validate()
  let source_width = original_range.right - original_range.left + 1
  if replacement is Some((part, next)) {
    ignore(next.validate())
    let owns = pivots.any(pivot => pivot.part == part)
    if pivots.search_by(pivot => pivot.part == part) is Some(index) {
      let previous = contexts[index].0
      let linked : Map[Int, Bool] = Map([])
      for cache in timelines {
        for (pivot, field) in cache.connections {
          if pivots.any(peer => peer.part == pivot.part) {
            linked[field] = true
          }
        }
      }
      guard Json(next.numberGroups) == Json(previous.numberGroups) &&
        Json(next.dateGroups.filter(group => !linked.contains(group.field))) ==
        Json(previous.dateGroups.filter(group => !linked.contains(group.field))) else {
        @failure.reject(
          "protected-content", "Only timeline date fields can change linked calendar groups",
        )
      }
      let slicers = self.affected_slicer_caches([pivots[index]])
      guard next.filters.all(filter => {
        filter.report ||
        filter.values is None ||
        (next.rows + next.columns).contains(filter.field) ||
        slicers.any(cache => cache.field == filter.field) ||
        timelines.any(cache => {
          cache.connections.any(pair => {
            pair.0.part == part && pair.1 == filter.field
          })
        })
      }) else {
        @failure.reject(
          "protected-content", "Unused pivot member filters require a linked analysis control",
        )
      }
      for cache in timelines {
        for (pivot, field) in cache.connections {
          if pivot.part == part {
            let before = previous.filters
              .iter()
              .find_first(filter => filter.field == field)
              .bind(filter => filter.values)
            let after = next.filters
              .iter()
              .find_first(filter => filter.field == field)
              .bind(filter => filter.values)
            let same = match (before, after) {
              (None, None) => true
              (Some(old), Some(next)) =>
                old.length() == next.length() &&
                old.all(value => next.contains(value))
              _ => false
            }
            guard same else {
              @failure.reject(
                "protected-content", "Use the timeline range controls to change its date filter",
              )
            }
          }
        }
      }
      contexts[index] = (next, contexts[index].1)
    }
    for index, context in contexts {
      contexts[index] = (
        {
          ..context.0,
          sourceSheet: next.sourceSheet,
          source: next.source,
          dateGroups: if owns {
            next.dateGroups
          } else {
            context.0.dateGroups
          },
        },
        context.1,
      )
    }
  }
  let settings = contexts[0].0
  guard contexts.all(context => {
    let next = context.0
    next.sourceSheet == settings.sourceSheet &&
    next.source == settings.source &&
    Json(next.numberGroups) == Json(settings.numberGroups) &&
    Json(next.dateGroups) == Json(settings.dateGroups) &&
    context.1 == contexts[0].1
  }) else {
    @failure.reject(
      "protected-content", "Shared pivot source or grouping is inconsistent",
    )
  }
  let dates : Map[Int, Bool] = Map([])
  let inputs = contexts.mapi((index, context) => {
    let connected : Array[Int] = []
    for cache in timelines {
      connected.append(
        cache.connections
        .filter(pair => pair.0.part == pivots[index].part)
        .map(pair => pair.1),
      )
    }
    for field in connected {
      guard !settings.numberGroups.any(group => group.field == field) else {
        @failure.reject(
          "protected-content", "Timeline fields cannot use numeric grouping",
        )
      }
      dates[field] = true
    }
    {
      ..context.0,
      filters: context.0.filters.map(filter => {
        if connected.contains(filter.field) {
          { ..filter, values: None, }
        } else {
          filter
        }
      }),
    }
  })
  let data = {
    ..self.pivot_cache(inputs[0], peers=inputs[1:].to_owned()),
    native_dates: dates.keys().to_array(),
  }
  let tree = Tree::new(self.part_xml(pivots[0].cache))
  let headers = tree
    .all(tree.one(0, "cacheFields").unwrap().id, "cacheField")
    .map(node => slicer_text(node, "name"))
  guard data.source_width == source_width &&
    headers.length() >= source_width &&
    headers[:source_width] == data.headers[:source_width] else {
    @failure.reject(
      "protected-content", "Pivot source headers changed; field remapping is required",
    )
  }
  for field in dates.keys() {
    ignore(data.timeline_bounds(field))
  }
  let result = contexts.mapi((index, context) => {
    let filters = context.0.filters.copy()
    for cache in timelines {
      for (pivot, field) in cache.connections {
        if pivot.part != pivots[index].part {
          continue
        }
        let report = filters.any(filter => {
          filter.field == field && filter.report
        })
        filters.retain(filter => filter.field != field)
        let values = data.timeline_members(field, cache.state.selection)
        if report || values is Some(_) {
          filters.push({ field, report, values, })
        }
      }
    }
    { ..context.0, filters, }
  })
  (data, result, contexts[0].1)
}

///|
fn PivotCache::timeline_bounds(
  self : PivotCache,
  field : Int,
) -> TimelineRange raise @failure.Failure {
  for value in self.items[field] {
    if value is Number(date) {
      pivot_date_check(date, self.date1904)
      // shortcut: Refresh of numeric 1900 dates before March needs the native leap-day mapping.
      guard self.date1904 || date >= 61 else {
        @failure.reject(
          "protected-content", "Early 1900 timeline dates require leap-day mapping",
        )
      }
    } else {
      guard value == Blank else {
        @failure.reject(
          "protected-content", "Timeline source contains non-date members",
        )
      }
    }
  }
  let dates = self.records.filter_map(record => {
    match self.items[field][record[field]] {
      Number(date) => Some(date)
      _ => None
    }
  })
  // shortcut: An all-blank date source needs a native empty-calendar bounds state before refresh can accept it.
  guard !dates.is_empty() else {
    @failure.reject(
      "protected-content", "Timeline source has no available dates",
    )
  }
  {
    start: pivot_date_text(
      dates.fold(init=dates[0], (a, b) => a.min(b)),
      self.date1904,
    ),
    end: pivot_date_text(
      dates.fold(init=dates[0], (a, b) => a.max(b)),
      self.date1904,
    ),
  }
}

///|
fn Session::refresh_timeline_part(
  self : Session,
  part : String,
  markup : String,
  edits : Array[(String, @xml.Edit)],
) -> Unit raise @failure.Failure {
  let original = self.part_xml(part)
  if original.source() != markup {
    let (document, edit) = pivot_root_edit(original, markup)
    self.parts[part] = document
    edits.push((part, edit))
  }
}
