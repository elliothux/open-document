///|
fn xlsx_analysis_catalog(
  session : @xlsx.Session,
  operation : String,
  request : Json,
) -> Json raise @failure.Failure {
  let revision = field_int(request, "revision")
  let sheet = field_string(request, "sheet")
  if operation == "slicersXlsx" {
    session.slicers(revision, sheet)
  } else {
    session.pivots(revision, sheet)
  }
}

///|
fn xlsx_pivot_settings(
  value : Json,
) -> @xlsx.PivotSettings raise @failure.Failure {
  guard value is Object(fields) &&
    fields.length() == 9 &&
    fields
    .keys()
    .all(k => {
      [
        "sourceSheet", "source", "rows", "columns", "filters", "subtotals", "numberGroups",
        "dateGroups", "values",
      ].contains(k)
    }) &&
    fields.get("rows") is Some(Array(rows)) &&
    fields.get("columns") is Some(Array(columns)) &&
    columns.length() <= 8 &&
    fields.get("filters") is Some(Array(filters)) &&
    filters.length() <= 8 &&
    fields.get("subtotals") is Some(Array(subtotals)) &&
    subtotals.length() <= 14 &&
    fields.get("numberGroups") is Some(Array(groups)) &&
    groups.length() <= 16 &&
    fields.get("dateGroups") is Some(Array(dates)) &&
    dates.length() + groups.length() <= 16 &&
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
    dateGroups: dates.map(group => {
      guard group is Object(fields) &&
        fields.length() == 2 &&
        fields.keys().all(key => ["field", "units"].contains(key)) &&
        fields.get("units") is Some(Array(units)) &&
        units.length() > 0 &&
        units.length() <= 4 else {
        @failure.reject("invalid-operation", "Invalid pivot calendar group")
      }
      @xlsx.PivotDateGroup::{
        field: field_int(group, "field"),
        units: units.map(value => {
          guard value is String(unit) else {
            @failure.reject("invalid-operation", "Invalid pivot calendar unit")
          }
          unit
        }),
      }
    }),
    numberGroups: groups.map(group => {
      guard group is Object(fields) &&
        fields.length() == 4 &&
        fields
        .keys()
        .all(key => ["field", "start", "end", "interval"].contains(key)) &&
        fields.get("interval") is Some(Number(interval, ..)) else {
        @failure.reject("invalid-operation", "Invalid pivot numeric group")
      }
      @xlsx.PivotNumberGroup::{
        field: field_int(group, "field"),
        start: match fields.get("start") {
          Some(Null) => None
          Some(Number(value, ..)) => Some(value)
          _ =>
            @failure.reject("invalid-operation", "Invalid pivot numeric start")
        },
        end: match fields.get("end") {
          Some(Null) => None
          Some(Number(value, ..)) => Some(value)
          _ => @failure.reject("invalid-operation", "Invalid pivot numeric end")
        },
        interval,
      }
    }),
    subtotals: subtotals.map(value => {
      guard value is Number(number, ..) &&
        number >= 0 &&
        number < 64 &&
        number == number.trunc() else {
        @failure.reject("invalid-operation", "Invalid pivot subtotal field")
      }
      number.to_int()
    }),
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
        fields.length() == 6 &&
        fields
        .keys()
        .all(k => {
          ["field", "aggregate", "name", "showDataAs", "baseField", "baseItem"].contains(
            k,
          )
        }) else {
        @failure.reject("invalid-operation", "Invalid pivot value field")
      }
      @xlsx.PivotValue::{
        field: field_int(value, "field"),
        aggregate: field_string(value, "aggregate"),
        showDataAs: field_string(value, "showDataAs"),
        baseField: match value {
          { "baseField": Null, .. } => None
          _ => Some(field_int(value, "baseField"))
        },
        baseItem: match value {
          { "baseItem": Null, .. } => None
          { "baseItem": String("previous"), .. } =>
            Some(@xlsx.PivotBaseItem::Previous)
          { "baseItem": String("next"), .. } => Some(@xlsx.PivotBaseItem::Next)
          { "baseItem": item, .. } =>
            Some(@xlsx.PivotBaseItem::Member(xlsx_value(item)))
          _ =>
            @failure.reject("invalid-operation", "Pivot base item is required")
        },
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
