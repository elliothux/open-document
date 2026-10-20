///|
fn xlsx_pivot_settings(
  value : Json,
) -> @xlsx.PivotSettings raise @failure.Failure {
  guard value is Object(fields) &&
    fields.length() == 6 &&
    fields
    .keys()
    .all(k => {
      ["sourceSheet", "source", "rows", "columns", "filters", "values"].contains(
        k,
      )
    }) &&
    fields.get("rows") is Some(Array(rows)) &&
    fields.get("columns") is Some(Array(columns)) &&
    columns.length() <= 8 &&
    fields.get("filters") is Some(Array(filters)) &&
    filters.length() <= 8 &&
    fields.get("values") is Some(Array(values)) &&
    rows.length() > 0 &&
    rows.length() <= 8 &&
    values.length() > 0 &&
    values.length() <= 8 else {
    @failure.reject("invalid-operation", "Invalid pivot settings")
  }
  {
    sourceSheet: field_string(value, "sourceSheet"),
    source: field_string(value, "source"),
    rows: rows.map(value => {
      guard value is Number(number, ..) &&
        number >= 0 &&
        number < 64 &&
        number == number.trunc() else {
        @failure.reject("invalid-operation", "Invalid pivot row field")
      }
      number.to_int()
    }),
    columns: columns.map(value => {
      guard value is Number(number, ..) &&
        number >= 0 &&
        number < 64 &&
        number == number.trunc() else {
        @failure.reject("invalid-operation", "Invalid pivot column field")
      }
      number.to_int()
    }),
    filters: filters.map(filter => {
      guard filter is Object(fields) &&
        fields.length() == 2 &&
        fields.keys().all(key => ["field", "values"].contains(key)) &&
        fields.get("values") is Some(values) else {
        @failure.reject("invalid-operation", "Invalid pivot report filter")
      }
      let values = match values {
        Null => None
        Array(values) if !values.is_empty() && values.length() <= 4096 =>
          Some(values.map(xlsx_value))
        _ => @failure.reject("invalid-operation", "Invalid pivot report values")
      }
      @xlsx.PivotFilter::{ field: field_int(filter, "field"), values, }
    }),
    values: values.map(value => {
      guard value is Object(fields) &&
        fields.length() == 3 &&
        fields.keys().all(k => ["field", "aggregate", "name"].contains(k)) else {
        @failure.reject("invalid-operation", "Invalid pivot value field")
      }
      @xlsx.PivotValue::{
        field: field_int(value, "field"),
        aggregate: field_string(value, "aggregate"),
        name: field_string(value, "name"),
      }
    }),
  }
}

///|
fn xlsx_pivot_edit(
  session : @xlsx.Session,
  revision : Int,
  sheet : String,
  change : Json,
) -> Json raise @failure.Failure {
  let action = field_string(change, "action")
  let keys = if action == "createPivot" {
    ["action", "name", "destination", "settings", "sourceRevision"]
  } else if action == "updatePivot" {
    ["action", "part", "settings", "sourceRevision"]
  } else {
    ["action", "part"]
  }
  guard change is Object(fields) &&
    fields.length() == keys.length() &&
    fields.keys().all(key => keys.contains(key)) else {
    @failure.reject("invalid-operation", "Invalid pivot command")
  }
  if action == "createPivot" || action == "updatePivot" {
    guard field_int(change, "sourceRevision") == revision else {
      @failure.reject(
        "stale-revision", "Preview the current source before changing a pivot",
      )
    }
  }
  if action == "createPivot" {
    ignore(
      session.create_pivot(
        revision,
        sheet,
        field_string(change, "name"),
        field_string(change, "destination"),
        xlsx_pivot_settings(fields["settings"]),
      ),
    )
  } else if action == "updatePivot" {
    ignore(
      session.update_pivot(
        revision,
        sheet,
        field_string(change, "part"),
        xlsx_pivot_settings(fields["settings"]),
      ),
    )
  } else if action == "deletePivot" {
    ignore(session.delete_pivot(revision, sheet, field_string(change, "part")))
  } else {
    ignore(session.refresh_pivot(revision, sheet, field_string(change, "part")))
  }
  session.query(sheet=Some(sheet))
}
