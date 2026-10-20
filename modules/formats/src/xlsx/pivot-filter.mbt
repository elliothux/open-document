///|
pub(all) struct PivotFilter {
  field : Int
  values : Array[Value]?
}

///|
pub impl ToJson for PivotFilter with fn to_json(self) {
  {
    "field": self.field,
    "values": self.values.map(value => Json(value)).unwrap_or(Json::null()),
  }
}

///|
pub extend PivotFilter with ToJson::{to_json}

///|
fn PivotSettings::page_rows(self : PivotSettings) -> Int {
  if self.filters.is_empty() {
    0
  } else {
    self.filters.length() + 1
  }
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
    PivotFilter::{ field: index, values: selected, }
  })
}
