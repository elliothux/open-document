///|
fn Session::affected_slicer_caches(
  self : Session,
  pivots : Array[PivotLocation],
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
    let connected = tree
      .slicer_children(root.id, "pivotTables")
      .any(list => {
        tree
        .slicer_children(list.id, "pivotTable")
        .any(node => {
          pivots.any(pivot => {
            node.attribute("name") == Some(pivot.name) &&
            self.slicer_pivot_sheet(node.attribute("tabId").unwrap_or("")) ==
            pivot.sheet
          })
        })
      })
    if connected {
      let cache = self.read_slicer_cache(path, known)
      members += cache.members.length()
      units += cache.source_units
      guard members <= 16384 && units <= 1048576 else {
        @failure.reject(
          "limit-exceeded", "Connected slicer members or text exceed budget",
        )
      }
      result.push(cache)
    }
  }
  result
}

///|
fn slicer_value_order(left : Value, right : Value) -> Int {
  let kind = fn(value : Value) {
    match value {
      Number(_) => 1
      Text(_) => 2
      Boolean(_) => 3
      Error(_) => 4
      Blank => 6
    }
  }
  let rank = kind(left).compare(kind(right))
  if rank != 0 {
    return rank
  }
  match (left, right) {
    (Number(a), Number(b)) => a.compare(b)
    (Text(a), Text(b)) => a[:].lexical_compare(b[:])
    (Boolean(a), Boolean(b)) =>
      (if a { 1 } else { 0 }).compare(if b { 1 } else { 0 })
    (Error(a), Error(b)) => {
      let codes = [
        "#NULL!", "#DIV/0!", "#VALUE!", "#REF!", "#NAME?", "#NUM!", "#N/A",
      ]
      codes
      .search_by(value => value == a)
      .unwrap_or(0)
      .compare(codes.search_by(value => value == b).unwrap_or(0))
    }
    _ => 0
  }
}

///|
fn Session::sync_slicer_state(
  self : Session,
  cache : SlicerCache,
  settings : PivotSettings,
  data : PivotCache,
  edits : Array[(String, @xml.Edit)],
) -> Unit raise @failure.Failure {
  guard cache.members.length() == data.axis_items(cache.field).length() else {
    @failure.reject(
      "protected-content", "Slicer cache does not enumerate every pivot member",
    )
  }
  let selected = settings.filters
    .iter()
    .find_first(filter => filter.field == cache.field)
    .bind(filter => filter.values)
    .map(values => {
      Map::from_array(values.map(value => (pivot_item_key(value), true)))
    })
  let filters = data.filter_indices(
    settings.filters.filter(filter => filter.field != cache.field),
  )
  let available : Map[Int, Bool] = Map([])
  let available_data = {
    ..data,
    source_filters: data.source_filters.filter(filter => filter.0 != cache.field),
  }
  for record in data.records {
    if available_data.record_visible(record, filters) {
      let index = match data.groups.get(cache.field) {
        Some(group) => group.indices[record[group.base()]]
        None => record[cache.field]
      }
      available[index] = true
    }
  }
  let original = self.part_xml(cache.part)
  let tree = Tree::new(original)
  let tabular = tree.slicer_node(tree.slicer_node(0, "data").id, "tabular")
  let items = tree.slicer_node(tabular.id, "items")
  let changes : Array[@xml.SourceChange] = []
  for node in tree.slicer_children(items.id, "i") {
    let index = natural(node.attribute("x").unwrap_or(""), 4095)
    let value = data.axis_items(cache.field)[index]
    let visible = selected
      .map(keys => keys.contains(pivot_item_key(value)))
      .unwrap_or(true)
    let no_data = cache.cross_filter != "none" && !available.contains(index)
    let attributes : Array[(String, String)] = []
    if visible != flag(node, "s") {
      attributes.push(("s", if visible { "1" } else { "0" }))
    }
    if no_data != flag(node, "nd") {
      attributes.push(("nd", if no_data { "1" } else { "0" }))
    }
    changes.append(metadata_changes(node, attributes))
  }
  let document = if changes.is_empty() {
    original
  } else {
    let (document, edit) = original.edit_source(changes)
    edits.push((cache.part, edit))
    document
  }
  let tree = Tree::new(document)
  let tabular = tree.slicer_node(tree.slicer_node(0, "data").id, "tabular")
  let items = tree.slicer_node(tabular.id, "items")
  let before = tree.slicer_children(items.id, "i")
  let ordered = before.map(node => {
    (node, natural(node.attribute("x").unwrap_or(""), 4095), flag(node, "nd"))
  })
  ordered.sort_by((a, b) => {
    let top = if cache.cross_filter == "showItemsWithDataAtTop" {
      (if a.2 { 1 } else { 0 }).compare(if b.2 { 1 } else { 0 })
    } else {
      0
    }
    if top != 0 {
      top
    } else {
      let value = slicer_value_order(
        data.axis_items(cache.field)[a.1],
        data.axis_items(cache.field)[b.1],
      )
      if cache.sort == "descending" {
        -value
      } else {
        value
      }
    }
  })
  let ordered = ordered.map(entry => entry.0)
  let document = if ordered.map(node => node.id) == before.map(node => node.id) {
    document
  } else {
    let markup = ordered
      .map(node => document.source()[node.start:node.end].to_owned())
      .join("")
    let (document, edit) = document.edit_source([
      {
        node: items.id,
        offset: items.opening_end - items.start,
        length: items.closing_start - items.opening_end,
        xml: markup,
      },
    ])
    edits.push((cache.part, edit))
    document
  }
  self.parts[cache.part] = document
}
