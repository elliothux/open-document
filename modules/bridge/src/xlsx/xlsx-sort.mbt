///|
#derive(@json.FromJson)
priv struct SortRequest {
  range : String
  rows : Bool
  header : Bool
  caseSensitive : Bool
  keys : Array[SortKeyRequest]
}

///|
#derive(@json.FromJson)
priv struct SortKeyRequest {
  index : @common.RequestInt
  descending : Bool
  customList : Array[String]?
  sortBy : String?
  color : String?
  iconSet : String?
  iconId : @common.RequestInt?
}

///|
fn xlsx_sort(change : Json) -> @model.SheetEdit raise @failure.Failure {
  guard change is { "keys": Array(keys), .. } &&
    keys.length() >= 1 &&
    keys.length() <= @model.SortKeys else {
    @failure.reject("invalid-operation", "Sorting requires bounded keys")
  }
  for key in keys {
    guard key is Object(fields) &&
      fields
      .iter()
      .all(pair => {
        match pair {
          (_, Null) => false
          (
            "index"
            | "descending"
            | "customList"
            | "sortBy"
            | "color"
            | "iconSet"
            | "iconId",
            _,
          ) => true
          _ => false
        }
      }) else {
      @failure.reject("invalid-operation", "Unknown sort key fields")
    }
    if fields.get("customList") is Some(value) {
      guard value is Array(items) && items.length() <= @model.SortListLabels else {
        @failure.reject("invalid-operation", "Invalid custom sort list")
      }
    }
  }
  let command : SortRequest = @common.request(change)
  @model.Sort(command.range, {
    rows: command.rows,
    header: command.header,
    case_sensitive: command.caseSensitive,
    keys: command.keys.map(key => {
      if key.iconSet is Some(_) || key.iconId is Some(_) {
        guard key.sortBy == Some("icon") &&
          key.iconSet is Some(set) &&
          !set.is_empty() &&
          key.iconId is Some(_) else {
          @failure.reject(
            "invalid-operation", "Conflicting or incomplete sort icon",
          )
        }
      }
      {
        index: key.index.value,
        descending: key.descending,
        custom_list: key.customList.unwrap_or([]),
        sort_by: key.sortBy.unwrap_or("value"),
        color: key.color.unwrap_or(""),
        icon_set: key.iconSet.unwrap_or(""),
        icon_id: key.iconId.map(icon => icon.value).unwrap_or(0),
      }
    }),
  })
}
