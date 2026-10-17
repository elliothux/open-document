///|
fn xlsx_filter(change : Json) -> @xlsx.SheetEdit raise @failure.Failure {
  guard change is { "columns": Array(columns), .. } && columns.length() <= 256 else {
    @failure.reject("invalid-operation", "Bounded filter columns are required")
  }
  @xlsx.SetFilter({
    range: field_string(change, "range"),
    columns: columns.map(column => {
      guard column is { "values": Array(values), .. } && values.length() <= 4096 else {
        @failure.reject(
          "invalid-operation", "Bounded filter values are required",
        )
      }
      {
        column: field_int(column, "column"),
        blank: xlsx_boolean(column, "blank"),
        values: values.map(value => {
          guard value is String(text) else {
            @failure.reject(
              "invalid-operation", "Filter labels must be strings",
            )
          }
          text
        }),
      }
    }),
  })
}
