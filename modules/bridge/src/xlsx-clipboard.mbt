///|
fn xlsx_copied_cells(value : Json) -> @xlsx.CopiedCells raise @failure.Failure {
  guard value is Object(fields) &&
    fields.length() == 7 &&
    value
    is {
      "cells": Array(rows),
      "merges": merges,
      "conditional": Array(conditional),
      "validations": Array(validations),
      ..
    } &&
    conditional.length() <= 4096 &&
    validations.length() <= 4096 &&
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
    conditional: conditional.map(rule => {
      let (ranges, anchor, settings) = xlsx_copied_rule(rule)
      @xlsx.CopiedConditional::{
        ranges,
        anchor,
        settings: xlsx_conditional_settings(settings),
      }
    }),
    validations: validations.map(rule => {
      let (ranges, anchor, settings) = xlsx_copied_rule(rule)
      @xlsx.CopiedValidation::{
        ranges,
        anchor,
        settings: xlsx_validation_settings(settings),
      }
    }),
  }
}

///|
fn xlsx_copied_rule(
  value : Json,
) -> (Array[@xlsx.Range], @xlsx.Address, Json) raise @failure.Failure {
  guard value is Object(fields) &&
    fields.length() == 3 &&
    value
    is { "ranges": Array(ranges), "anchor": anchor, "settings": settings, .. } &&
    !ranges.is_empty() &&
    ranges.length() <= 4096 &&
    anchor is Object(point) &&
    point.length() == 2 else {
    @failure.reject("invalid-operation", "Invalid copied rule")
  }
  (
    ranges.map(value => {
      guard value is Object(fields) && fields.length() == 4 else {
        @failure.reject("invalid-operation", "Invalid copied rule range")
      }
      @xlsx.Range::{
        top: field_int(value, "top"),
        left: field_int(value, "left"),
        bottom: field_int(value, "bottom"),
        right: field_int(value, "right"),
      }
    }),
    { row: field_int(anchor, "row"), column: field_int(anchor, "column"), },
    settings,
  )
}
