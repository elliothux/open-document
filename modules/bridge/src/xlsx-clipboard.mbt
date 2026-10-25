///|
fn xlsx_copied_cells(value : Json) -> @xlsx.CopiedCells raise @failure.Failure {
  guard value is Object(fields) &&
    fields.length() == 10 &&
    value
    is {
      "cells": Array(rows),
      "merges": merges,
      "conditional": Array(conditional),
      "validations": Array(validations),
      "hyperlinks": Array(hyperlinks),
      "notes": notes,
      "sparklines": Array(sparklines),
      ..
    } &&
    conditional.length() <= 4096 &&
    validations.length() <= 4096 &&
    hyperlinks.length() <= 4096 &&
    sparklines.length() <= 256 &&
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
      let value = xlsx_value(content)
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
    sparklines: sparklines.map(item => {
      guard item is Object(fields) &&
        fields.length() == 3 &&
        item is { "cell": Object(cell), "source": source, .. } &&
        cell.length() == 2 else {
        @failure.reject("invalid-operation", "Invalid copied sparkline fields")
      }
      let source = match source {
        Null => None
        Object(fields) if fields.length() == 4 =>
          Some(@xlsx.Range::{
            top: field_int(source, "top"),
            left: field_int(source, "left"),
            bottom: field_int(source, "bottom"),
            right: field_int(source, "right"),
          })
        _ =>
          @failure.reject(
            "invalid-operation", "Invalid copied sparkline source",
          )
      }
      @xlsx.CopiedSparkline::{
        cell: {
          row: field_int(Json::object(cell), "row"),
          column: field_int(Json::object(cell), "column"),
        },
        source,
        kind: field_string(item, "kind"),
      }
    }),
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
    hyperlinks: hyperlinks.map(link => {
      guard link is Object(fields) &&
        fields.length() == 4 &&
        link
        is {
          "range": Object(range),
          "display": display,
          "tooltip": tooltip,
          ..
        } &&
        range.length() == 4 else {
        @failure.reject("invalid-operation", "Invalid copied hyperlink fields")
      }
      let optional = fn(value : Json) raise @failure.Failure {
        match value {
          Null => None
          String(value) => Some(value)
          _ =>
            @failure.reject(
              "invalid-operation", "Invalid copied hyperlink text",
            )
        }
      }
      @xlsx.CopiedHyperlink::{
        range: {
          top: field_int(Json::object(range), "top"),
          left: field_int(Json::object(range), "left"),
          bottom: field_int(Json::object(range), "bottom"),
          right: field_int(Json::object(range), "right"),
        },
        target: field_string(link, "target"),
        display: optional(display),
        tooltip: optional(tooltip),
      }
    }),
    notes: match notes {
      Null => None
      Object(fields) if fields.length() == 4 => {
        guard fields.get("vml") is Some(vml) else {
          @failure.reject("invalid-operation", "Missing copied note VML")
        }
        let vml = match vml {
          Null => None
          String(value) => Some(value)
          _ => @failure.reject("invalid-operation", "Invalid copied note VML")
        }
        Some(@xlsx.CopiedNotes::{
          comments: field_string(notes, "comments"),
          vml,
          threads: copied_thread_xml(fields, "threads"),
          people: copied_thread_xml(fields, "people"),
        })
      }
      _ => @failure.reject("invalid-operation", "Invalid copied note fields")
    },
  }
}

///|
fn copied_thread_xml(
  fields : Map[String, Json],
  name : String,
) -> String? raise @failure.Failure {
  match fields.get(name) {
    Some(Null) => None
    Some(String(text)) => Some(text)
    _ =>
      @failure.reject(
        "invalid-operation", "Invalid copied native thread fields",
      )
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
