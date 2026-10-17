///|
fn xlsx_data(
  session : @xlsx.Session,
  operation : String,
  request : Json,
) -> Json raise @failure.Failure {
  guard request is { "settings": settings, .. } else {
    @failure.reject("invalid-operation", "Data operation settings are required")
  }
  let revision = field_int(request, "revision")
  let sheet = field_string(request, "sheet")
  if operation == "duplicatesXlsx" {
    session.duplicates(revision, sheet, xlsx_duplicate_settings(settings))
  } else {
    session.text_columns(revision, sheet, xlsx_column_settings(settings))
  }
}

///|
fn xlsx_column_settings(
  value : Json,
) -> @xlsx.TextColumnSettings raise @failure.Failure {
  guard value is Object(fields) &&
    fields.length() >= 2 &&
    fields.length() <= 4 &&
    fields
    .keys()
    .all(k => ["range", "delimiter", "breaks", "types", "formulas"].contains(k)) &&
    fields.contains("delimiter") != fields.contains("breaks") else {
    @failure.reject("invalid-operation", "Invalid text to columns settings")
  }
  let split = if fields.contains("breaks") {
    guard fields.get("breaks") is Some(Array(breaks)) &&
      !breaks.is_empty() &&
      breaks.length() < 4096 else {
      @failure.reject("invalid-operation", "Invalid fixed-width positions")
    }
    @xlsx.Fixed(
      breaks.map(value => {
        guard value is Number(number, ..) &&
          number >= 1 &&
          number <= 65534 &&
          number == number.trunc() else {
          @failure.reject("invalid-operation", "Invalid fixed-width position")
        }
        number.to_int()
      }),
    )
  } else {
    @xlsx.Delimited(field_string(value, "delimiter"))
  }
  let types = match fields.get("types") {
    None => []
    Some(Array(values)) if values.length() <= 4096 =>
      values.map(value => {
        guard value is String(kind) else {
          @failure.reject("invalid-operation", "Invalid column type")
        }
        kind
      })
    _ => @failure.reject("invalid-operation", "Invalid column types")
  }
  {
    range: field_string(value, "range"),
    split,
    types,
    formulas: if fields.contains("formulas") {
      xlsx_boolean(value, "formulas")
    } else {
      false
    },
  }
}

///|
fn xlsx_duplicate_settings(
  value : Json,
) -> @xlsx.DuplicateSettings raise @failure.Failure {
  guard value is Object(fields) &&
    fields.length() == 3 &&
    fields.keys().all(k => ["range", "header", "columns"].contains(k)) &&
    fields.get("columns") is Some(Array(columns)) &&
    !columns.is_empty() &&
    columns.length() <= 4096 else {
    @failure.reject("invalid-operation", "Invalid duplicate settings")
  }
  {
    range: field_string(value, "range"),
    header: xlsx_boolean(value, "header"),
    columns: columns.map(value => {
      guard value is Number(number, ..) &&
        number >= 1 &&
        number <= 16384 &&
        number == number.trunc() else {
        @failure.reject(
          "invalid-operation", "Invalid duplicate comparison column",
        )
      }
      number.to_int()
    }),
  }
}
