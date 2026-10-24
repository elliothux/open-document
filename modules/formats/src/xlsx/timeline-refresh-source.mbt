///|
fn Session::refresh_timeline_data(
  self : Session,
  cache : TimelineCache,
  data : PivotCache,
  settings : PivotSettings,
  edits : Array[(String, @xml.Edit)],
) -> Unit raise @failure.Failure {
  let links = self.relationships()
  guard links.filter(link => !link.external && link.target == cache.pivot_cache)
    is [owner] &&
    owner.owner == self.main &&
    owner.kind == relationship_uri + "pivotCacheDefinition" &&
    links.filter(link => link.owner == cache.pivot_cache) is [records] &&
    !records.external &&
    records.kind == relationship_uri + "pivotCacheRecords" &&
    links
    .filter(link => !link.external && link.target == records.target)
    .length() ==
    1 &&
    !links.any(link => link.owner == records.target) else {
    @failure.reject(
      "protected-content", "Shared or extended timeline date resources require coordinated refresh",
    )
  }
  let original = self.part_xml(cache.pivot_cache)
  pivot_plain_source(original)
  let tree = Tree::new(original)
  let list = tree.one(0, "extLst").unwrap()
  guard list.attributes.is_empty() &&
    tree.all(list.id, "ext") is [ext] &&
    ext.attributes.length() == 1 &&
    tree.children.get(list.id).unwrap_or([]).length() == 1 &&
    tree.children.get(ext.id).unwrap_or([]).length() == 1 else {
    @failure.reject(
      "protected-content", "Unknown timeline date metadata requires preservation support",
    )
  }
  ignore(timeline_source_field(original, cache.source, true))
  let (plain, _) = original.edit_source([sheet_node_removal(tree, list)])
  pivot_cache_profile(plain, records.id)
  let fields = tree.all(tree.one(0, "cacheFields").unwrap().id, "cacheField")
  let old_range = Range::parse(timeline_origin(original)[1])
  let old_width = old_range.right - old_range.left + 1
  ignore(
    pivot_read_groups(
      Tree::new(plain),
      self.date1904,
      old_width,
      settings.values.map(value => value.name),
    ),
  )
  guard fields.length() >= old_width &&
    pivot_source_field(data.headers, cache.source) < data.source_width else {
    @failure.reject(
      "protected-content", "Timeline date source fields require remapping",
    )
  }
  // Independent date caches store original source records, regardless of report grouping.
  let data = {
    ..data,
    headers: data.headers[:data.source_width].to_owned(),
    items: data.items[:data.source_width].to_owned(),
    styles: data.styles[:data.source_width].to_owned(),
    groups: Map([]),
    axes: Map([]),
  }
  let counts = fields.map(field => {
    tree
    .one(field.id, "sharedItems")
    .map(items => tree.children.get(items.id).unwrap_or([]).length())
    .unwrap_or(0)
  })
  let old_records = self.part_xml(records.target)
  pivot_plain_source(old_records)
  let rows = Tree::new(old_records)
  let entries = rows.all(0, "r")
  guard entries.length().to_int64() * old_width.to_int64() <= 65536 &&
    natural(old_records.nodes()[0].attribute("count").unwrap_or(""), 65536) ==
    entries.length() &&
    natural(original.nodes()[0].attribute("recordCount").unwrap_or(""), 65536) ==
    entries.length() else {
    @failure.reject(
      "protected-content", "Timeline date record count is inconsistent or exceeds budget",
    )
  }
  for node in old_records.nodes() {
    conditional_node(
      rows,
      node,
      if node.name == "pivotCacheRecords" {
        ["count"]
      } else if node.name == "r" || node.name == "m" {
        []
      } else {
        ["v"]
      },
      if node.name == "pivotCacheRecords" {
        ["r"]
      } else if node.name == "r" {
        ["x", "n", "s", "b", "e", "m"]
      } else {
        []
      },
    )
  }
  for row in entries {
    let values = rows.children.get(row.id).unwrap_or([])
    guard values.length() == old_width else {
      @failure.reject(
        "protected-content", "Timeline date record width is inconsistent",
      )
    }
    for field, value in values {
      if value.name == "x" {
        guard counts[field] > 0 else {
          @failure.reject(
            "protected-content", "Timeline date record index is unavailable",
          )
        }
        ignore(natural(value.attribute("v").unwrap_or(""), counts[field] - 1))
      }
    }
  }
  let markup = data.definition(
    self.sheets[self.sheet_index(settings.sourceSheet)].name,
    settings.source,
    records.id,
  )
  let generated = @xml.Document::parse(
    @utf8.encode(markup),
    cache.pivot_cache,
    64,
    2097152,
  )
  let (document, _) = generated.edit_source([
    insertion(
      generated.nodes()[0],
      "<extLst xmlns='\{spreadsheet_uri}'><ext uri='{5DA0FC9A-693D-419C-AD59-312A39285967}'><odT:timelinePivotCacheDefinition xmlns:odT='\{timeline_uri}' timelineData='1'/></ext></extLst>",
    ),
  ])
  self.refresh_timeline_part(cache.pivot_cache, document.source(), edits)
  self.refresh_timeline_part(records.target, data.record_markup(), edits)
}
