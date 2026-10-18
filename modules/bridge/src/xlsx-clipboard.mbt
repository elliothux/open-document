///|
fn xlsx_copied_cells(value : Json) -> @xlsx.CopiedCells raise @failure.Failure {
  guard value is Object(fields) &&
    fields.length() == 5 &&
    value is { "cells": Array(rows), "merges": merges, .. } &&
    !rows.is_empty() &&
    rows.length() <= 4096 else {
    @failure.reject("invalid-operation", "Expected copied cells")
  }
  let mut count = 0
  let cells = rows.map(row => {
    guard row is Array(columns) && !columns.is_empty() else {
      @failure.reject("invalid-operation", "Expected copied cell columns")
    }
    count += columns.length()
    guard count <= 4096 else {
      @failure.reject("limit-exceeded", "Copied cells exceed budget")
    }
    columns.map(cell => {
      guard cell is Object(fields) &&
        fields.length() == 3 &&
        cell is { "value": content, "formula": formula, "format": format, .. } &&
        content is Object(parts) &&
        parts.length() == 2 else {
        @failure.reject("invalid-operation", "Invalid copied cell fields")
      }
      let value = match field_string(content, "kind") {
        "blank" => {
          guard content is { "value": Null, .. } else {
            @failure.reject("invalid-operation", "Expected blank value")
          }
          @xlsx.Blank
        }
        "text" => @xlsx.Text(field_string(content, "value"))
        "error" => @xlsx.Error(field_string(content, "value"))
        "number" => @xlsx.Number(xlsx_number(content, "value"))
        "boolean" => @xlsx.Boolean(xlsx_boolean(content, "value"))
        _ => @failure.reject("invalid-operation", "Unknown copied value kind")
      }
      let formula = match formula {
        Null => None
        String(value) => Some(value)
        _ =>
          @failure.reject("invalid-operation", "Expected copied cell formula")
      }
      @xlsx.CopiedCell::{ value, formula, format: xlsx_cell_format(format), }
    })
  })
  let (_, ranges) = xlsx_copied_format({
    "cells": rows.map(row => {
      if row is Array(columns) {
        columns.map(cell => {
          if cell is { "format": format, .. } {
            format
          } else {
            Json::null()
          }
        })
      } else {
        []
      }
    }),
    "merges": merges,
  })
  {
    top: field_int(value, "top"),
    left: field_int(value, "left"),
    date1904: xlsx_boolean(value, "date1904"),
    cells,
    merges: ranges,
  }
}
