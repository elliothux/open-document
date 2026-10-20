///|
fn xlsx_filter(change : Json) -> @xlsx.SheetEdit raise @failure.Failure {
  @xlsx.SetFilter({
    range: field_string(change, "range"),
    columns: xlsx_filter_columns(change),
  })
}

///|
fn xlsx_filter_columns(
  change : Json,
) -> Array[@xlsx.FilterColumn] raise @failure.Failure {
  guard change is { "columns": Array(columns), .. } && columns.length() <= 256 else {
    @failure.reject("invalid-operation", "Bounded filter columns are required")
  }
  columns.map(column => {
    let rule = match field_string(column, "kind") {
      "relativeDate" => {
        guard column is Object(fields) &&
          fields.keys().all(k => ["kind", "column", "period"].contains(k)) else {
          @failure.reject(
            "invalid-operation", "Unknown relative date filter field",
          )
        }
        @xlsx.Relative(field_string(column, "period"), None)
      }
      "calendar" => {
        guard column is Object(fields) &&
          fields
          .keys()
          .all(k => ["kind", "column", "unit", "value"].contains(k)) else {
          @failure.reject("invalid-operation", "Unknown calendar filter field")
        }
        @xlsx.Calendar(field_string(column, "unit"), field_int(column, "value"))
      }
      "color" => {
        guard column is Object(fields) &&
          fields
          .keys()
          .all(k => ["kind", "column", "color", "cellColor"].contains(k)) else {
          @failure.reject("invalid-operation", "Unknown color filter field")
        }
        let value = match column {
          { "color": Null, .. } => None
          { "color": String(value), .. } => Some(value)
          _ =>
            @failure.reject(
              "invalid-operation", "Color filter requires RGB or null",
            )
        }
        @xlsx.Color(value, cell_color=xlsx_boolean(column, "cellColor"))
      }
      "dates" => {
        guard column is Object(fields) &&
          fields
          .keys()
          .all(k => ["kind", "column", "groups", "values", "blank"].contains(k)) &&
          column is { "groups": Array(groups), "values": Array(values), .. } &&
          !groups.is_empty() &&
          groups.length() + values.length() <= 4096 else {
          @failure.reject(
            "invalid-operation", "Bounded date groups and labels are required",
          )
        }
        let strings = fn(items : Array[Json]) raise @failure.Failure {
          items.map(item => {
            guard item is String(value) else {
              @failure.reject(
                "invalid-operation", "Date groups and labels must be strings",
              )
            }
            value
          })
        }
        @xlsx.Dates(
          strings(groups),
          values=strings(values),
          blank=xlsx_boolean(column, "blank"),
        )
      }
      "average" => {
        guard column is Object(fields) &&
          fields.keys().all(k => ["kind", "column", "above"].contains(k)) else {
          @failure.reject("invalid-operation", "Unknown average filter field")
        }
        @xlsx.Average(above=xlsx_boolean(column, "above"))
      }
      "rank" => {
        guard column is Object(fields) &&
          fields
          .keys()
          .all(k => ["kind", "column", "value", "top", "percent"].contains(k)) else {
          @failure.reject("invalid-operation", "Unknown rank filter field")
        }
        @xlsx.Rank(
          field_int(column, "value"),
          top=xlsx_boolean(column, "top"),
          percent=xlsx_boolean(column, "percent"),
        )
      }
      "values" => {
        guard column is { "values": Array(values), .. } &&
          values.length() <= 4096 else {
          @failure.reject(
            "invalid-operation", "Bounded filter values are required",
          )
        }
        @xlsx.Values(
          values.map(value => {
            guard value is String(text) else {
              @failure.reject(
                "invalid-operation", "Filter labels must be strings",
              )
            }
            text
          }),
          blank=xlsx_boolean(column, "blank"),
        )
      }
      "custom" => {
        guard column is { "conditions": Array(conditions), .. } &&
          conditions.length() >= 1 &&
          conditions.length() <= 2 else {
          @failure.reject(
            "invalid-operation", "One or two custom filter conditions are required",
          )
        }
        @xlsx.Custom(
          conditions.map(condition => {
            operator: field_string(condition, "operator"),
            value: field_string(condition, "value"),
          }),
          all=xlsx_boolean(column, "all"),
        )
      }
      _ => @failure.reject("invalid-operation", "Unknown filter kind")
    }
    { column: field_int(column, "column"), rule, }
  })
}

///|
fn xlsx_calendar_date(request : Json) -> String? raise @failure.Failure {
  match request {
    { "date": String(value), .. } => Some(value)
    { "date": _, .. } =>
      @failure.reject("invalid-operation", "Invalid current calendar date")
    _ => None
  }
}
