///|
pub(all) struct PivotFilter {
  field : Int
  report : Bool
  values : Array[Value]?
}

///|
pub impl ToJson for PivotFilter with fn to_json(self) {
  {
    "field": self.field,
    "report": self.report,
    "values": self.values.map(value => Json(value)).unwrap_or(Json::null()),
  }
}

///|
pub extend PivotFilter with ToJson::{to_json}

///|
fn PivotSettings::page_rows(self : PivotSettings) -> Int {
  let filters = self.page_filters()
  if filters.is_empty() {
    0
  } else {
    filters.length() + 1
  }
}

///|
fn PivotSettings::page_filters(self : PivotSettings) -> Array[PivotFilter] {
  self.filters.filter(filter => filter.report)
}

///|
fn PivotCache::filter_indices(
  self : PivotCache,
  filters : Array[PivotFilter],
) -> Array[(Int, Map[Int, Bool]?)] {
  filters.map(filter => {
    (
      filter.field,
      filter.values.map(values => {
        let keys = Map::from_array(
          values.map(value => (pivot_item_key(value), true)),
        )
        let selected : Map[Int, Bool] = Map([])
        for at, value in self.axis_items(filter.field) {
          if keys.contains(pivot_item_key(value)) {
            selected[at] = true
          }
        }
        selected
      }),
    )
  })
}

///|
fn PivotCache::record_visible(
  self : PivotCache,
  record : Array[Int],
  filters : Array[(Int, Map[Int, Bool]?)],
) -> Bool {
  !filters.any(filter => {
    filter.1
    .map(keys => {
      let item = match self.groups.get(filter.0) {
        Some(group) => group.indices[record[group.base()]]
        None => record[filter.0]
      }
      !keys.contains(item)
    })
    .unwrap_or(false)
  })
}

///|
fn pivot_field_items(
  cache : Tree,
  index : Int,
) -> Array[Value] raise @failure.Failure {
  let fields = cache.all(cache.one(0, "cacheFields").unwrap().id, "cacheField")
  guard fields.get(index) is Some(field) else {
    @failure.reject("protected-content", "Pivot field cache is unavailable")
  }
  let grouped = cache
    .one(field.id, "fieldGroup")
    .bind(group => cache.one(group.id, "groupItems"))
  let node = match grouped {
    Some(_) => grouped
    None => cache.one(field.id, "sharedItems")
  }
  guard node is Some(node) else {
    @failure.reject("protected-content", "Pivot field items are unavailable")
  }
  let items = cache.children.get(node.id).unwrap_or([])
  guard items.length() <= 4096 else {
    @failure.reject("limit-exceeded", "Pivot field items exceed budget")
  }
  items.map(pivot_cache_value)
}

///|
fn pivot_read_member_filters(
  tree : Tree,
  cache : Tree,
  width : Int,
) -> Array[PivotFilter] raise @failure.Failure {
  let result : Array[PivotFilter] = []
  let fields = tree.all(tree.one(0, "pivotFields").unwrap().id, "pivotField")
  for index, field in fields {
    if field.attribute("axis") == Some("axisPage") {
      continue
    }
    let items = tree
      .one(field.id, "items")
      .map(node => {
        tree
        .all(node.id, "item")
        .filter(item => item.attribute("t") != Some("default"))
      })
      .unwrap_or([])
    if !items.any(item => flag(item, "h")) {
      continue
    }
    guard index < width else {
      @failure.reject(
        "protected-content", "Filtering a derived calendar level requires support",
      )
    }
    let values = pivot_field_items(cache, index)
    guard values.length() <= 4096 && items.length() == values.length() else {
      @failure.reject(
        "protected-content", "Pivot axis items disagree with the cache",
      )
    }
    let selected = items
      .filter(item => !flag(item, "h"))
      .map(item => {
        values[natural(item.attribute("x").unwrap_or(""), values.length() - 1)]
      })
    result.push({ field: index, report: false, values: Some(selected), })
  }
  result
}

///|
fn PivotSettings::body(self : PivotSettings, range : Range) -> Range {
  { ..range, top: range.top + self.page_rows(), }
}

///|
fn pivot_filter_value(value : Value) -> Unit raise @failure.Failure {
  let text = value.display()
  guard text.length() <= 32767 && @xml.valid_text(text) else {
    @failure.reject("invalid-operation", "Invalid pivot filter value")
  }
  if value is Number(number) {
    guard !number.is_nan() && !number.is_inf() else {
      @failure.reject("invalid-operation", "Non-finite pivot filter value")
    }
  }
  if value is Error(error) {
    guard ["#NULL!", "#DIV/0!", "#VALUE!", "#REF!", "#NAME?", "#NUM!", "#N/A"].contains(
      error,
    ) else {
      @failure.reject("invalid-operation", "Unknown pivot filter error")
    }
  }
  guard value != Text("") else {
    @failure.reject(
      "invalid-operation", "Use a blank pivot filter value for empty text",
    )
  }
}

///|
fn pivot_cache_value(node : @xml.Node) -> Value raise @failure.Failure {
  let text = node.attribute("v").unwrap_or("")
  let value = match node.name {
    "m" => Blank
    "s" => Text(decode_text(text))
    "n" => Number(number(text))
    "b" => Boolean(flag(node, "v"))
    "e" => Error(text)
    _ =>
      @failure.reject(
        "protected-content", "Unsupported pivot filter cache value",
      )
  }
  pivot_filter_value(value)
  value
}

///|
fn PivotCache::filter_caption(self : PivotCache, filter : PivotFilter) -> Value {
  match filter.values {
    Some([value]) => if value == Blank { Text("(blank)") } else { value }
    Some(values) if values.length() != self.items[filter.field].length() =>
      Text("(Multiple Items)")
    _ => Text("(All)")
  }
}

///|
fn pivot_read_filters(
  tree : Tree,
  cache : Tree,
) -> Array[PivotFilter] raise @failure.Failure {
  let pages = tree
    .one(0, "pageFields")
    .map(node => {
      conditional_node(tree, node, ["count"], ["pageField"])
      tree.all(node.id, "pageField")
    })
    .unwrap_or([])
  guard pages.length() <= 8 else {
    @failure.reject("limit-exceeded", "Pivot report fields exceed budget")
  }
  let fields = tree.all(tree.one(0, "pivotFields").unwrap().id, "pivotField")
  let caches = cache.all(cache.one(0, "cacheFields").unwrap().id, "cacheField")
  pages.map(page => {
    conditional_node(tree, page, ["fld", "hier", "item"], [])
    guard page.attribute("hier").unwrap_or("-1") == "-1" else {
      @failure.reject(
        "protected-content", "Hierarchical pivot report fields require support",
      )
    }
    let index = natural(page.attribute("fld").unwrap_or(""), 63)
    guard fields.get(index) is Some(field) &&
      caches.get(index) is Some(cached) &&
      cache.one(cached.id, "sharedItems") is Some(shared) else {
      @failure.reject(
        "malformed-xlsx", "Pivot report field cache is unavailable",
      )
    }
    let values = cache.children
      .get(shared.id)
      .unwrap_or([])
      .map(pivot_cache_value)
    let items = tree
      .one(field.id, "items")
      .map(node => tree.all(node.id, "item"))
      .unwrap_or([])
    guard values.length() <= 4096 && items.length() == values.length() else {
      @failure.reject(
        "limit-exceeded", "Pivot report items exceed budget or disagree with cache",
      )
    }
    let selected = if flag(field, "multipleItemSelectionAllowed") {
      guard page.attribute("item") is None else {
        @failure.reject(
          "protected-content", "Conflicting pivot report selection",
        )
      }
      Some(
        items
        .filter(item => !flag(item, "h"))
        .map(item => {
          values[natural(item.attribute("x").unwrap_or(""), values.length() - 1)]
        }),
      )
    } else if page.attribute("item") is Some(item) {
      let at = natural(item, items.length() - 1)
      guard !flag(items[at], "h") else {
        @failure.reject(
          "protected-content", "Hidden pivot report selection is inconsistent",
        )
      }
      Some([
        values[natural(
          items[at].attribute("x").unwrap_or(""),
          values.length() - 1,
        )],
      ])
    } else if items.any(item => flag(item, "h")) {
      Some(
        items
        .filter(item => !flag(item, "h"))
        .map(item => {
          values[natural(item.attribute("x").unwrap_or(""), values.length() - 1)]
        }),
      )
    } else {
      None
    }
    PivotFilter::{ field: index, report: true, values: selected, }
  })
}
