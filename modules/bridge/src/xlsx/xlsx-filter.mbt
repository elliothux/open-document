///|
fn xlsx_filter(change : Json) -> @model.SheetEdit raise @failure.Failure {
  @model.SetFilter({
    range: field_string(change, "range"),
    columns: xlsx_filter_columns(change),
  })
}

///|
fn xlsx_filter_columns(
  change : Json,
) -> Array[@model.FilterColumn] raise @failure.Failure {
  guard change is { "columns": Array(columns), .. } && columns.length() <= 256 else {
    @failure.reject("invalid-operation", "Bounded filter columns are required")
  }
  columns.map(column => {
    let rule = match field_string(column, "kind") {
      "icon" => {
        guard column is Object(fields) &&
          fields
          .keys()
          .all(key => ["kind", "column", "iconSet", "iconId"].contains(key)) else {
          @failure.reject("invalid-operation", "Unknown icon filter field")
        }
        let id = match column {
          { "iconId": Null, .. } => None
          { "iconId": Number(_), .. } => Some(field_int(column, "iconId"))
          _ =>
            @failure.reject(
              "invalid-operation", "Icon filter requires an index or null",
            )
        }
        @model.Icon(field_string(column, "iconSet"), id)
      }
      "relativeDate" => {
        guard column is Object(fields) &&
          fields.keys().all(k => ["kind", "column", "period"].contains(k)) else {
          @failure.reject(
            "invalid-operation", "Unknown relative date filter field",
          )
        }
        @model.Relative(field_string(column, "period"), None)
      }
      "calendar" => {
        guard column is Object(fields) &&
          fields
          .keys()
          .all(k => ["kind", "column", "unit", "value"].contains(k)) else {
          @failure.reject("invalid-operation", "Unknown calendar filter field")
        }
        @model.Calendar(
          field_string(column, "unit"),
          field_int(column, "value"),
        )
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
        @model.Color(value, cell_color=field_boolean(column, "cellColor"))
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
        @model.Dates(
          strings(groups),
          values=strings(values),
          blank=field_boolean(column, "blank"),
        )
      }
      "average" => {
        guard column is Object(fields) &&
          fields.keys().all(k => ["kind", "column", "above"].contains(k)) else {
          @failure.reject("invalid-operation", "Unknown average filter field")
        }
        @model.Average(above=field_boolean(column, "above"))
      }
      "rank" => {
        guard column is Object(fields) &&
          fields
          .keys()
          .all(k => ["kind", "column", "value", "top", "percent"].contains(k)) else {
          @failure.reject("invalid-operation", "Unknown rank filter field")
        }
        @model.Rank(
          field_int(column, "value"),
          top=field_boolean(column, "top"),
          percent=field_boolean(column, "percent"),
        )
      }
      "values" => {
        guard column is { "values": Array(values), .. } &&
          values.length() <= 4096 else {
          @failure.reject(
            "invalid-operation", "Bounded filter values are required",
          )
        }
        @model.Values(
          values.map(value => {
            guard value is String(text) else {
              @failure.reject(
                "invalid-operation", "Filter labels must be strings",
              )
            }
            text
          }),
          blank=field_boolean(column, "blank"),
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
        @model.Custom(
          conditions.map(condition => {
            operator: field_string(condition, "operator"),
            value: field_string(condition, "value"),
          }),
          all=field_boolean(column, "all"),
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
