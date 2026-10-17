///|
fn xlsx_sort(change : Json) -> @xlsx.SheetEdit raise @failure.Failure {
  guard change is { "keys": Array(keys), .. } &&
    keys.length() >= 1 &&
    keys.length() <= 16 else {
    @failure.reject("invalid-operation", "Sorting requires bounded keys")
  }
  @xlsx.Sort(field_string(change, "range"), {
    rows: xlsx_boolean(change, "rows"),
    header: xlsx_boolean(change, "header"),
    case_sensitive: xlsx_boolean(change, "caseSensitive"),
    keys: keys.map(key => {
      guard key is Object(fields) &&
        fields
        .keys()
        .all(name => {
          ["index", "descending", "customList", "sortBy", "color"].contains(
            name,
          )
        }) else {
        @failure.reject("invalid-operation", "Unknown sort key fields")
      }
      let custom_list = match fields.get("customList") {
        None => []
        Some(Array(values)) if values.length() <= 4096 =>
          values.map(value => {
            guard value is String(text) else {
              @failure.reject(
                "invalid-operation", "Custom sort labels must be strings",
              )
            }
            text
          })
        _ => @failure.reject("invalid-operation", "Invalid custom sort list")
      }
      {
        index: field_int(key, "index"),
        descending: xlsx_boolean(key, "descending"),
        custom_list,
        sort_by: match fields.get("sortBy") {
          None => "value"
          Some(String(kind)) => kind
          _ => @failure.reject("invalid-operation", "Invalid sort kind")
        },
        color: match fields.get("color") {
          None => ""
          Some(String(color)) => color
          _ => @failure.reject("invalid-operation", "Invalid sort color")
        },
      }
    }),
  })
}
