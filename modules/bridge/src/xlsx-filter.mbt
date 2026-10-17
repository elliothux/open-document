///|
fn xlsx_filter(change : Json) -> @xlsx.SheetEdit raise @failure.Failure {
  guard change is { "columns": Array(columns), .. } && columns.length() <= 256 else {
    @failure.reject("invalid-operation", "Bounded filter columns are required")
  }
  @xlsx.SetFilter({
    range: field_string(change, "range"),
    columns: columns.map(column => {
      let rule = match field_string(column, "kind") {
        "dates" => {
          guard column is Object(fields) &&
            fields
            .keys()
            .all(k => {
              ["kind", "column", "groups", "values", "blank"].contains(k)
            }) &&
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
    }),
  })
}
