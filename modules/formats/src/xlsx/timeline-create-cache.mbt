///|
fn Session::timeline_creation_cache(
  self : Session,
  pivot : PivotLocation,
  field : Int,
  settings : PivotSettings,
  data : PivotCache,
  parts : Map[String, @xml.Document],
  created : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
) -> (TimelineCache, @xml.Document) raise @failure.Failure {
  let paths = self.timeline_parts(
    self.main,
    self.workbook,
    timeline_cache_extension,
    "timelineCacheRefs",
    "timelineCacheRef",
    "TimelineCache",
  )
  let matches = self
    .affected_timeline_caches([pivot])
    .filter(cache => {
      cache.connections.any(pair => pair.0.part == pivot.part && pair.1 == field)
    })
  guard matches.length() <= 1 else {
    @failure.reject(
      "protected-content", "Ambiguous timeline cache for pivot date field",
    )
  }
  if matches is [cache] {
    return (cache, self.workbook)
  }
  guard paths.length() < 64 else {
    @failure.reject("limit-exceeded", "Timeline cache count exceeds budget")
  }
  let names : Map[String, Bool] = Map([])
  let uids : Map[String, Bool] = Map([])
  for part in paths {
    let node = self.part_xml(part).nodes()[0]
    let name = slicer_text(node, "name").to_upper()
    guard !names.contains(name) else {
      @failure.reject("protected-content", "Duplicate timeline cache name")
    }
    names[name] = true
    if node.attribute(
        "uid",
        uri="http://schemas.microsoft.com/office/spreadsheetml/2016/revision10",
      )
      is Some(uid) {
      guard !uids.contains(uid.to_upper()) else {
        @failure.reject("protected-content", "Duplicate timeline cache UID")
      }
      uids[uid.to_upper()] = true
    }
  }
  let uid = slicer_creation_uid(uids, paths.length(), "00000004")
  for key in self.formula_names().sources.keys() {
    names[key.1.to_upper()] = true
  }
  for table in self.formula_names().tables {
    names[table.name.to_upper()] = true
  }
  let name = for id in 1..<=16384 {
    let value = "odTimelineCache\{id}"
    if !names.contains(value.to_upper()) {
      break value
    }
  } nobreak {
    @failure.reject("limit-exceeded", "Timeline cache names exhausted")
  }
  let (_, records) = self.pivot_settings(pivot, shared=true)
  let record_tree = Tree::new(self.part_xml(records))
  guard record_tree
    .all(0, "r")
    .all(row => {
      record_tree.children
      .get(row.id)
      .unwrap_or([])
      .get(field)
      .map(node => ["x", "m"].contains(node.name))
      .unwrap_or(false)
    }) else {
    @failure.reject(
      "protected-content", "Timeline dates require indexed native records",
    )
  }
  let dates = self.timeline_date_members(
    pivot, field, settings, data, parts, edits,
  )
  let minimum = dates.fold(init=dates[0], (value, next) => value.min(next))
  let maximum = dates.fold(init=dates[0], (value, next) => value.max(next))
  let bounds : TimelineRange = {
    start: pivot_date_text(minimum, self.date1904),
    end: pivot_date_text(maximum, self.date1904),
  }
  let selection = settings.filters
    .iter()
    .find_first(filter => filter.field == field)
    .bind(filter => filter.values)
    .map(values => {
      guard !values.is_empty() && values.all(value => value is Number(_)) else {
        @failure.reject(
          "protected-content", "Clear empty or blank date member selections before inserting a timeline",
        )
      }
      let selected = values.map(value => {
        match value {
          Number(value) => value
          _ => 0.0
        }
      })
      let first = selected.fold(init=selected[0], (value, next) => {
        value.min(next)
      })
      let last = selected.fold(init=selected[0], (value, next) => {
        value.max(next)
      })
      guard dates.filter(date => date >= first && date <= last).length() ==
        selected.length() else {
        @failure.reject(
          "protected-content", "Noncontiguous date selections require timeline mapping",
        )
      }
      TimelineRange::{
        start: pivot_date_text(first, self.date1904),
        end: pivot_date_text(last, self.date1904),
      }
    })
  let original = parts
    .get(pivot.cache)
    .unwrap_or_else(() => self.part_xml(pivot.cache))
  let (data_part, data_link) = self.create_sheet_resource(
    self.main,
    "pivotCacheDefinition",
    original.source(),
    parts,
    created,
    edits,
  )
  let (_, record_link) = self.create_sheet_resource(
    data_part,
    "pivotCacheRecords",
    record_tree.document.source(),
    parts,
    created,
    edits,
  )
  let document = parts[data_part]
  let root = document.nodes()[0]
  let attr = root.attributes
    .iter()
    .find_first(attr => {
      attr.name == "id" &&
      attr.uri == relationship_uri[:relationship_uri.length() - 1].to_owned()
    })
    .unwrap()
  let (document, edit) = document.edit_source([
    {
      node: root.id,
      offset: attr.start - root.start,
      length: attr.end - attr.start,
      xml: escaped_attribute(record_link),
    },
    insertion(
      root,
      "<odX:extLst xmlns:odX='\{spreadsheet_uri}'><odX:ext uri='{5DA0FC9A-693D-419C-AD59-312A39285967}'><odT:timelinePivotCacheDefinition xmlns:odT='\{timeline_uri}' timelineData='1'/></odX:ext></odX:extLst>",
    ),
  ])
  parts[data_part] = document
  edits.push((data_part, edit))
  let ids = self.workbook
    .nodes()
    .filter(node => node.uri == spreadsheet_uri && node.name == "pivotCache")
    .map(node => natural(node.attribute("cacheId").unwrap_or(""), 2147483647))
  let id = for id in 1..<=257 {
    if !ids.contains(id) {
      break id
    }
  } nobreak {
    @failure.reject(
      "limit-exceeded", "Timeline data cache identities exhausted",
    )
  }
  let (workbook, edit) = timeline_cache_directory(self.workbook, id, data_link)
  edits.push((self.main, edit))
  let selected = selection
    .map(range => {
      "<selection startDate='\{escaped_attribute(range.start)}' endDate='\{escaped_attribute(range.end)}'/>"
    })
    .unwrap_or("")
  let state = "<state singleRangeFilterState='1' minimalRefreshVersion='3' lastRefreshVersion='6' pivotCacheId='\{id}' filterType='\{if selection is Some(_) {"dateBetween"} else {"unknown"}}'>\{selected}<bounds startDate='\{bounds.start}' endDate='\{bounds.end}'/></state>"
  let tab = self.slicer_sheet_id(pivot.sheet)
  let source = "<timelineCacheDefinition xmlns='\{timeline_uri}'\{uid} name='\{name}' sourceName='\{escaped_attribute(encoded_text(data.headers[field]))}'><pivotTables><pivotTable tabId='\{tab}' name='\{escaped_attribute(encoded_text(pivot.name))}'/></pivotTables>\{state}</timelineCacheDefinition>"
  let (part, relation) = self.create_sheet_resource(
    self.main,
    "TimelineCache",
    source,
    parts,
    created,
    edits,
  )
  let (workbook, edit) = analysis_reference(
    workbook,
    timeline_cache_extension,
    "timelineCacheRefs",
    "timelineCacheRef",
    relation,
    payload_uri=timeline_uri,
  )
  edits.push((self.main, edit))
  let candidate = { ..self, parts, workbook, }
  (candidate.read_timeline_cache(part, self.pivot_locations()), workbook)
}
