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
      index: field_int(key, "index"),
      descending: xlsx_boolean(key, "descending"),
    }),
  })
}
