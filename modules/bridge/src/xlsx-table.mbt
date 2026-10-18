///|
fn xlsx_table_edit(change : Json) -> @xlsx.SheetEdit raise @failure.Failure {
  let action = field_string(change, "action")
  if [
      "tableFilter", "tableFilterClear", "tableFilterRemove", "tableFilterReapply",
    ].contains(action) {
    let keys = if action == "tableFilter" {
      ["action", "id", "columns"]
    } else {
      ["action", "id"]
    }
    guard change is Object(fields) &&
      fields.length() == keys.length() &&
      fields.keys().all(key => keys.contains(key)) else {
      @failure.reject("invalid-operation", "Invalid table filter fields")
    }
    let id = field_int(change, "id")
    return match action {
      "tableFilter" => @xlsx.TableFilter(id, xlsx_filter_columns(change))
      "tableFilterClear" => @xlsx.TableFilterClear(id)
      "tableFilterRemove" => @xlsx.TableFilterRemove(id)
      _ => @xlsx.TableFilterReapply(id)
    }
  }
  if action == "tableTotals" ||
    action == "tableTotal" ||
    action == "tableColumnFormula" ||
    action == "resizeTable" ||
    action == "createTable" ||
    action == "renameTable" ||
    action == "renameTableColumn" {
    let keys = if action == "tableTotals" {
      ["action", "id", "visible"]
    } else if action == "tableTotal" {
      ["action", "id", "column", "total"]
    } else if action == "tableColumnFormula" {
      ["action", "id", "column", "formula"]
    } else if action == "resizeTable" {
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
    "tableTotals" =>
      @xlsx.TableTotals(
        field_int(change, "id"),
        xlsx_boolean(change, "visible"),
      )
    "tableTotal" => {
      guard change is { "total": Object(fields) as total, .. } else {
        @failure.reject("invalid-operation", "Expected column total settings")
      }
      let kind = field_string(total, "kind")
      let keys = match kind {
        "none" => ["kind"]
        "label" => ["kind", "text"]
        "formula" => ["kind", "formula"]
        "aggregate" => ["kind", "function"]
        _ => @failure.reject("invalid-operation", "Unknown column total kind")
      }
      guard fields.length() == keys.length() &&
        fields.keys().all(key => keys.contains(key)) else {
        @failure.reject("invalid-operation", "Invalid column total fields")
      }
      let setting = match kind {
        "none" => @xlsx.TableTotal::Clear
        "label" => @xlsx.TableTotal::Label(field_string(total, "text"))
        "formula" => @xlsx.TableTotal::Formula(field_string(total, "formula"))
        _ => @xlsx.TableTotal::Aggregate(field_string(total, "function"))
      }
      @xlsx.TableColumnTotal(
        field_int(change, "id"),
        field_int(change, "column"),
        setting,
      )
    }
    "tableColumnFormula" => {
      let formula = match change {
        { "formula": Null, .. } => None
        { "formula": String(text), .. } => Some(text)
        _ => @failure.reject("invalid-operation", "Expected a formula or null")
      }
      @xlsx.TableColumnFormula(
        field_int(change, "id"),
        field_int(change, "column"),
        formula,
      )
    }
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
