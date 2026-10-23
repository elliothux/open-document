///|
pub(all) enum PivotBaseItem {
  Previous
  Next
  Member(Value)
} derive(Eq)

///|
pub impl ToJson for PivotBaseItem with fn to_json(self) {
  match self {
    Previous => Json("previous")
    Next => Json("next")
    Member(value) => value.to_json()
  }
}

///|
pub extend PivotBaseItem with Eq::{equal, not_equal}

///|
pub extend PivotBaseItem with ToJson::{to_json}

///|
fn pivot_compare_mode(mode : String) -> Bool {
  ["difference", "percent", "percentDiff"].contains(mode)
}

///|
fn pivot_read_base_item(
  field : @xml.Node,
  cache : Tree,
  date1904~ : Bool = false,
) -> PivotBaseItem? raise @failure.Failure {
  guard field.attribute("baseItem") is Some(item) else { return None }
  match item {
    "1048828" => Some(Previous)
    "1048829" => Some(Next)
    _ => {
      let base = natural(field.attribute("baseField").unwrap_or(""), 63)
      let items = pivot_field_items(cache, base, date1904~)
      let at = natural(item, items.length() - 1)
      Some(Member(items[at]))
    }
  }
}

///|
fn PivotCache::base_item_index(
  self : PivotCache,
  field : Int,
  value : Value,
) -> Int raise @failure.Failure {
  // shortcut: Retired group labels stay protected until grouped member editing can preserve them.
  self
  .axis_items(field)
  .search_by(item => pivot_item_key(item) == pivot_item_key(value))
  .unwrap_or_error(
    @failure.Failure(
      code="protected-content",
      message="Selected pivot base item is unavailable in the current grouping",
      part="",
      offset=-1,
    ),
  )
}

///|
fn PivotCache::base_item_markup(
  self : PivotCache,
  value : PivotValue,
) -> String raise @failure.Failure {
  let item = match value.baseItem {
    None => return ""
    Some(Previous) => 1048828
    Some(Next) => 1048829
    Some(Member(item)) => self.base_item_index(value.baseField.unwrap(), item)
  }
  " baseItem=\"\{item}\""
}
