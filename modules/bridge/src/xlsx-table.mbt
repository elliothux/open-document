///|
fn xlsx_table_edit(change : Json) -> @xlsx.SheetEdit raise @failure.Failure {
  let action = field_string(change, "action")
  if action == "resizeTable" ||
    action == "createTable" ||
    action == "renameTable" ||
    action == "renameTableColumn" {
    let keys = if action == "resizeTable" {
      ["action", "id", "range"]
    } else if action == "createTable" {
      ["action", "range", "name"]
    } else if action == "renameTable" {
      ["action", "id", "name"]
    } else {
      ["action", "id", "column", "name"]
    }
    guard change is Object(fields) &&
      fields.length() == keys.length() &&
      fields.keys().all(key => keys.contains(key)) else {
      @failure.reject("invalid-operation", "Invalid table edit fields")
    }
  }
  match action {
    "resizeTable" =>
      @xlsx.ResizeTable(field_int(change, "id"), field_string(change, "range"))
    "createTable" =>
      @xlsx.CreateTable(
        field_string(change, "range"),
        field_string(change, "name"),
      )
    "group" | "ungroup" =>
      @xlsx.GroupOutline(
        field_string(change, "axis"),
        field_int(change, "first"),
        field_int(change, "last"),
        field_string(change, "action") == "ungroup",
      )
    "collapseGroup" =>
      @xlsx.CollapseOutline(
        field_string(change, "axis"),
        field_int(change, "first"),
        field_int(change, "last"),
        field_int(change, "level"),
        xlsx_boolean(change, "collapsed"),
      )
    "clearOutline" => @xlsx.ClearOutline(field_string(change, "axis"))
    "outlineSummary" =>
      @xlsx.OutlineSummary(
        field_string(change, "axis"),
        xlsx_boolean(change, "after"),
      )
    "renameTable" =>
      @xlsx.RenameTable(field_int(change, "id"), field_string(change, "name"))
    "renameTableColumn" =>
      @xlsx.RenameTableColumn(
        field_int(change, "id"),
        field_int(change, "column"),
        field_string(change, "name"),
      )
    _ => @failure.reject("invalid-operation", "Unknown table or outline action")
  }
}
