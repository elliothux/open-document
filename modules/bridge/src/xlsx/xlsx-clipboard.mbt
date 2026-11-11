///|
#derive(@json.FromJson)
priv struct CopiedCellsOriginRequest {
  top : @common.RequestInt
  left : @common.RequestInt
  date1904 : Bool
}

///|
#derive(@json.FromJson)
priv struct CopiedCellRequest {
  value : CellValueRequest
  formula : @common.RequiredNullable[String]
  format : CellFormatRequest
}

///|
#derive(@json.FromJson)
priv struct CopiedAddressRequest {
  row : @common.RequestInt
  column : @common.RequestInt
}

///|
fn copied_address(value : Json) -> @model.Address raise @failure.Failure {
  guard value is Object(fields) && fields.length() == 2 else {
    @failure.reject("invalid-operation", "Invalid copied cell address")
  }
  let input : CopiedAddressRequest = @common.request(value)
  { row: input.row.value, column: input.column.value, }
}

///|
#derive(@json.FromJson)
priv struct CopiedRangeRequest {
  top : @common.RequestInt
  left : @common.RequestInt
  bottom : @common.RequestInt
  right : @common.RequestInt
}

///|
fn copied_range(value : Json) -> @model.Range raise @failure.Failure {
  guard value is Object(fields) && fields.length() == 4 else {
    @failure.reject("invalid-operation", "Invalid copied range")
  }
  let input : CopiedRangeRequest = @common.request(value)
  {
    top: input.top.value,
    left: input.left.value,
    bottom: input.bottom.value,
    right: input.right.value,
  }
}

///|
#derive(@json.FromJson)
priv struct CopiedSparklineRequest {
  cell : Json
  source : Json
  kind : String
}

///|
#derive(@json.FromJson)
priv struct CopiedHyperlinkRequest {
  range : Json
  target : String
  display : @common.RequiredNullable[String]
  tooltip : @common.RequiredNullable[String]
}

///|
#derive(@json.FromJson)
priv struct CopiedNotesRequest {
  comments : String
  vml : @common.RequiredNullable[String]
  threads : @common.RequiredNullable[String]
  people : @common.RequiredNullable[String]
}

///|
fn xlsx_copied_cells(value : Json) -> @model.CopiedCells raise @failure.Failure {
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
    conditional.length() <= @model.CopiedRuleRanges &&
    validations.length() <= @model.CopiedRuleRanges &&
    hyperlinks.length() <= @model.CopiedHyperlinkCount &&
    sparklines.length() <= @model.SparklineCount &&
    !rows.is_empty() &&
    rows.length() <= @model.CellFragmentCells else {
    @failure.reject("invalid-operation", "Expected copied cells")
  }
  let mut count = 0
  let cells = rows.map(row => {
    guard row is Array(columns) && !columns.is_empty() else {
      @failure.reject("invalid-operation", "Expected copied cell columns")
    }
    guard columns.length() <= @model.CellFragmentCells - count else {
      @failure.reject("limit-exceeded", "Copied cells exceed budget")
    }
    count += columns.length()
    columns.map(cell => {
      guard cell is Object(fields) && fields.length() == 3 else {
        @failure.reject("invalid-operation", "Invalid copied cell fields")
      }
      let input : CopiedCellRequest = @common.request(cell)
      @model.CopiedCell::{
        value: input.value.value,
        formula: input.formula.value,
        format: input.format.value,
      }
    })
  })
  let ranges = copied_merge_items(merges).map(copied_range)
  let origin : CopiedCellsOriginRequest = @common.request(value)
  {
    top: origin.top.value,
    left: origin.left.value,
    date1904: origin.date1904,
    cells,
    merges: ranges,
    sparklines: sparklines.map(item => {
      guard item is Object(fields) && fields.length() == 3 else {
        @failure.reject("invalid-operation", "Invalid copied sparkline fields")
      }
      let input : CopiedSparklineRequest = @common.request(item)
      @model.CopiedSparkline::{
        cell: copied_address(input.cell),
        source: if input.source is Null {
          None
        } else {
          Some(copied_range(input.source))
        },
        kind: input.kind,
      }
    }),
    conditional: conditional.map(rule => {
      let (ranges, anchor, settings) = xlsx_copied_rule(rule)
      @model.CopiedConditional::{
        ranges,
        anchor,
        settings: xlsx_conditional_settings(settings),
      }
    }),
    validations: validations.map(rule => {
      let (ranges, anchor, settings) = xlsx_copied_rule(rule)
      @model.CopiedValidation::{
        ranges,
        anchor,
        settings: @common.request(settings),
      }
    }),
    hyperlinks: hyperlinks.map(link => {
      guard link is Object(fields) && fields.length() == 4 else {
        @failure.reject("invalid-operation", "Invalid copied hyperlink fields")
      }
      let input : CopiedHyperlinkRequest = @common.request(link)
      @model.CopiedHyperlink::{
        range: copied_range(input.range),
        target: input.target,
        display: input.display.value,
        tooltip: input.tooltip.value,
      }
    }),
    notes: match notes {
      Null => None
      Object(fields) if fields.length() == 4 => {
        let input : CopiedNotesRequest = @common.request(notes)
        Some(@model.CopiedNotes::{
          comments: input.comments,
          vml: input.vml.value,
          threads: input.threads.value,
          people: input.people.value,
        })
      }
      _ => @failure.reject("invalid-operation", "Invalid copied note fields")
    },
  }
}

///|
fn xlsx_copied_rule(
  value : Json,
) -> (Array[@model.Range], @model.Address, Json) raise @failure.Failure {
  guard value is Object(fields) &&
    fields.length() == 3 &&
    value
    is { "ranges": Array(ranges), "anchor": anchor, "settings": settings, .. } &&
    !ranges.is_empty() &&
    ranges.length() <= @model.CopiedRuleRanges else {
    @failure.reject("invalid-operation", "Invalid copied rule")
  }
  (ranges.map(copied_range), copied_address(anchor), settings)
}
