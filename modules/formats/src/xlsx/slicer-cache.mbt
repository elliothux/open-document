///|
priv struct SlicerMember {
  index : Int32
  value : Value
  selected : Bool
  hasData : Bool
}

///|
priv struct SlicerCache {
  part : String
  name : String
  source : String
  pivot_cache : String
  field : Int32
  pivots : Array[PivotLocation]
  members : Array[SlicerMember]
  sort : String
  cross_filter : String
  custom_sort : Bool
  show_missing : Bool
  source_units : Int32
}

///|
fn Session::slicer_pivot_cache(
  self : Session,
  id : String,
) -> String raise @failure.Failure {
  let id = natural(id, 2147483647)
  let tree = Tree::new(self.workbook)
  let entries = tree
    .one(tree.root("workbook").id, "pivotCaches")
    .map(node => tree.all(node.id, "pivotCache"))
    .unwrap_or([])
  guard entries.filter(node => {
      node
      .attribute("cacheId")
      .map(value => natural(value, 2147483647) == id)
      .unwrap_or(false)
    })
    is [entry] &&
    entry.attribute(
      "id",
      uri=relationship_uri[:relationship_uri.length() - 1].to_owned(),
    )
    is Some(relation) &&
    self
    .relationships()
    .filter(link => link.owner == self.main && link.id == relation)
    is [link] &&
    !link.external &&
    link.kind == relationship_uri + "pivotCacheDefinition" else {
    @failure.reject(
      "protected-content", "Slicer pivot cache identity is unavailable",
    )
  }
  link.target
}

///|
fn Session::slicer_pivot_sheet(
  self : Session,
  id : String,
) -> String raise @failure.Failure {
  let id = natural(id, 2147483647)
  let tree = Tree::new(self.workbook)
  let entries = tree
    .one(tree.root("workbook").id, "sheets")
    .map(node => tree.all(node.id, "sheet"))
    .unwrap_or([])
  guard entries.filter(node => {
      node
      .attribute("sheetId")
      .map(value => natural(value, 2147483647) == id)
      .unwrap_or(false)
    })
    is [entry] &&
    entry.attribute(
      "id",
      uri=relationship_uri[:relationship_uri.length() - 1].to_owned(),
    )
    is Some(relation) &&
    self
    .relationships()
    .filter(link => link.owner == self.main && link.id == relation)
    is [link] &&
    !link.external &&
    link.kind == relationship_uri + "worksheet" else {
    @failure.reject(
      "protected-content", "Slicer pivot worksheet identity is unavailable",
    )
  }
  ignore(self.sheet_index(link.target))
  link.target
}

///|
fn Session::read_slicer_cache(
  self : Session,
  part : String,
  pivots : Array[PivotLocation],
) -> SlicerCache raise @failure.Failure {
  let document = self.part_xml(part)
  pivot_plain_source(document)
  let tree = Tree::new(document)
  let root = document.nodes()[0]
  guard root.name == "slicerCacheDefinition" else {
    @failure.reject("protected-content", "Expected a slicer cache definition")
  }
  slicer_node_profile(tree, root, ["name", "sourceName"], [
    "pivotTables", "data",
  ])
  let name = slicer_text(root, "name")
  let source = slicer_text(root, "sourceName")
  let data = tree.slicer_node(root.id, "data")
  slicer_node_profile(tree, data, [], ["tabular"])
  let tabular = tree.slicer_node(data.id, "tabular")
  slicer_node_profile(
    tree,
    tabular,
    [
      "pivotCacheId", "sortOrder", "customListSort", "showMissing", "crossFilter",
    ],
    ["items"],
  )
  let pivot_cache = self.slicer_pivot_cache(
    tabular.attribute("pivotCacheId").unwrap_or(""),
  )
  let cache = Tree::new(self.part_xml(pivot_cache))
  let fields = cache.all(
    cache.one(cache.root("pivotCacheDefinition").id, "cacheFields").unwrap().id,
    "cacheField",
  )
  guard fields.length() <= 80 else {
    @failure.reject("limit-exceeded", "Slicer source fields exceed budget")
  }
  let matching = fields
    .mapi((index, node) => {
      (index, decode_text(node.attribute("name").unwrap_or("")))
    })
    .filter(field => field.1 == source)
  guard matching is [(field, _)] else {
    @failure.reject(
      "protected-content", "Slicer source field is missing or ambiguous",
    )
  }
  let cached = fields[field]
  let items = cache
    .one(cached.id, "fieldGroup")
    .bind(group => cache.one(group.id, "groupItems"))
  let items = match items {
    Some(_) => items
    None => cache.one(cached.id, "sharedItems")
  }
  guard items is Some(items) else {
    @failure.reject("protected-content", "Slicer field members are unavailable")
  }
  let slots = cache.children.get(items.id).unwrap_or([])
  let source_units = slots.fold(init=0, (units, node) => {
    units + node.attribute("v").unwrap_or("").length()
  })
  guard slots.length() <= 4096 && source_units <= 1048576 else {
    @failure.reject(
      "limit-exceeded", "Slicer field members or text exceed budget",
    )
  }
  let values = pivot_field_items(cache, field, date1904=self.date1904)
  guard !values.is_empty() && values.length() <= 4096 else {
    @failure.reject("limit-exceeded", "Slicer members exceed budget")
  }
  let connections = tree.slicer_node(root.id, "pivotTables")
  slicer_node_profile(tree, connections, [], ["pivotTable"])
  let entries = tree.slicer_children(connections.id, "pivotTable")
  guard !entries.is_empty() && entries.length() <= 16 else {
    @failure.reject("limit-exceeded", "Slicer pivot connections exceed budget")
  }
  let seen : Map[String, Bool] = Map([])
  let connections = entries.map(node => {
    slicer_node_profile(tree, node, ["tabId", "name"], [])
    let sheet = self.slicer_pivot_sheet(node.attribute("tabId").unwrap_or(""))
    let name = slicer_text(node, "name")
    guard pivots.filter(pivot => pivot.sheet == sheet && pivot.name == name)
      is [pivot] &&
      pivot.cache == pivot_cache &&
      !seen.contains(pivot.part) else {
      @failure.reject(
        "protected-content", "Slicer connection disagrees with its pivot cache",
      )
    }
    seen[pivot.part] = true
    pivot
  })
  let items = tree.slicer_node(tabular.id, "items")
  slicer_node_profile(tree, items, ["count"], ["i"])
  let entries = tree.slicer_children(items.id, "i")
  guard entries.length() <= 4096 else {
    @failure.reject("limit-exceeded", "Slicer members exceed budget")
  }
  guard !entries.is_empty() &&
    items
    .attribute("count")
    .map(count => natural(count, 4096) == entries.length())
    .unwrap_or(true) else {
    @failure.reject("protected-content", "Slicer member count is inconsistent")
  }
  let indices : Map[Int32, Bool] = Map([])
  let members = entries.map(node => {
    slicer_node_profile(tree, node, ["x", "s", "nd"], [])
    let index = natural(node.attribute("x").unwrap_or(""), values.length() - 1)
    guard !indices.contains(index) else {
      @failure.reject("protected-content", "Duplicate slicer member index")
    }
    indices[index] = true
    SlicerMember::{
      index,
      value: values[index],
      selected: flag(node, "s"),
      hasData: !flag(node, "nd"),
    }
  })
  let sort = tabular.attribute("sortOrder").unwrap_or("ascending")
  let cross_filter = tabular
    .attribute("crossFilter")
    .unwrap_or("showItemsWithDataAtTop")
  guard ["ascending", "descending"].contains(sort) &&
    ["none", "showItemsWithDataAtTop", "showItemsWithNoData"].contains(
      cross_filter,
    ) else {
    @failure.reject(
      "protected-content", "Unsupported slicer sort or cross-filter mode",
    )
  }
  {
    part,
    name,
    source,
    pivot_cache,
    field,
    pivots: connections,
    members,
    sort,
    cross_filter,
    custom_sort: flag(tabular, "customListSort", fallback=true),
    show_missing: flag(tabular, "showMissing", fallback=true),
    source_units,
  }
}

///|
fn Session::slicer_caches(
  self : Session,
  wanted : Array[String],
) -> Map[String, SlicerCache] raise @failure.Failure {
  let parts = self.slicer_parts(
    self.main,
    self.workbook,
    slicer_cache_extension,
    "slicerCaches",
    "slicerCache",
    "slicerCache",
  )
  if parts.is_empty() {
    return Map([])
  }
  let pivots = self.pivot_locations()
  let result : Map[String, SlicerCache] = Map([])
  let names : Map[String, Bool] = Map([])
  let mut members = 0
  let mut units = 0
  for part in parts {
    let root = self.part_xml(part).nodes()[0]
    guard root.uri == slicer_uri && root.name == "slicerCacheDefinition" else {
      @failure.reject("protected-content", "Expected a slicer cache definition")
    }
    let name = slicer_text(root, "name")
    guard !names.contains(name) else {
      @failure.reject("protected-content", "Duplicate slicer cache name")
    }
    names[name] = true
    if !wanted.contains(name) {
      continue
    }
    let cache = self.read_slicer_cache(part, pivots)
    members += cache.members.length()
    units += cache.source_units
    guard members <= 16384 && units <= 1048576 && !result.contains(cache.name) else {
      @failure.reject(
        "limit-exceeded", "Slicer cache names or members exceed budget",
      )
    }
    result[cache.name] = cache
  }
  result
}
