///|
pub fn chart_data(
  kind : String,
  title : String,
  bytes : Bytes,
  budget : @archive.Budget,
  hole_size~ : Int? = None,
  legend~ : String? = None,
) -> @layout.ChartData raise @failure.Failure {
  let workbook = Session::open(bytes, budget)
  defer workbook.close()
  guard workbook.query(
      sheet=Some(workbook.sheets[0].id),
      range=Some("A1:XFD1048576"),
    )
    is { "cells": Array(cells), .. } else {
    @failure.reject("invalid-chart", "Chart workbook is unavailable")
  }
  let values : Map[(Int, Int), Json] = Map([])
  let mut rows = 0
  let mut columns = 0
  for cell in cells {
    guard cell
      is {
        "row": Number(row, ..),
        "column": Number(column, ..),
        "value": value,
        "formula": Null,
        ..
      } &&
      row >= 1 &&
      row <= 257 &&
      column >= 1 &&
      column <= 9 else {
      @failure.reject(
        "invalid-chart", "Chart data exceeds dimensions or contains formulas",
      )
    }
    rows = rows.max(row.to_int())
    columns = columns.max(column.to_int())
    values[(row.to_int(), column.to_int())] = value
  }
  guard rows >= 2 && columns >= 2 else {
    @failure.reject(
      "invalid-chart", "Chart data requires a header row, categories and numeric series",
    )
  }
  let text = fn(row : Int, column : Int) raise @failure.Failure {
    match values.get((row, column)) {
      Some({ "kind": String("text"), "value": String(text), .. }) => text
      Some({ "kind": String("number"), "value": Number(value, ..), .. }) =>
        value.to_string()
      Some({ "kind": String("blank"), .. }) | None => ""
      _ =>
        @failure.reject("invalid-chart", "Chart labels require text or numbers")
    }
  }
  let result : @layout.ChartData = {
    kind,
    legend: legend.unwrap_or(
      if ["pie", "doughnut"].contains(kind) {
        "right"
      } else {
        "bottom"
      },
    ),
    hole_size: if kind == "doughnut" {
      Some(hole_size.unwrap_or(75))
    } else {
      hole_size
    },
    title,
    label: text(1, 1),
    categories: Array::makei(rows - 1, index => text(index + 2, 1)),
    series: Array::makei(columns - 1, index => {
      let column = index + 2
      {
        name: text(1, column),
        values: Array::makei(rows - 1, index => {
          let row = index + 2
          match values.get((row, column)) {
            Some({ "kind": String("number"), "value": Number(value, ..), .. }) =>
              Some(value)
            Some({ "kind": String("text"), "value": String(""), .. })
            | Some({ "kind": String("blank"), .. })
            | None => None
            _ =>
              @failure.reject(
                "invalid-chart", "Chart values require numbers or blanks",
              )
          }
        }),
      }
    }),
  }
  result.validate()
  result
}

///|
/// Creates an independent plain-value chart workbook with literal labels and typed numbers.
pub fn chart_workbook(
  data : @layout.ChartData,
  budget : @archive.Budget,
) -> Bytes raise @failure.Failure {
  data.validate()
  let blank = Session::create(budget)
  defer blank.close()
  let rows = StringBuilder()
  for row in 0..<=data.categories.length() {
    rows <+ "<row r='\{row+1}'>"
    for column in 0..<=data.series.length() {
      let address : Address = { row: row + 1, column: column + 1, }
      let value : Value = if row == 0 {
        Text(
          if column == 0 {
            data.label
          } else {
            data.series[column - 1].name
          },
        )
      } else if column == 0 {
        Text(data.categories[row - 1])
      } else {
        data.series[column - 1].values[row - 1]
        .map(value => Value::Number(value))
        .unwrap_or(Blank)
      }
      let (kind, content) = content_xml("", {
        value,
        formula: None,
        keep_shared: false,
      })
      rows <+ "<c r='\{address.name()}'\{kind}>\{content}</c>"
    }
    rows <+ "</row>"
  }
  let range : Range = {
    top: 1,
    left: 1,
    bottom: data.categories.length() + 1,
    right: data.series.length() + 1,
  }
  let worksheet = blank.sheets[0].document
    .source()
    .replace(old="ref=\"A1\"", new="ref=\"\{range.name()}\"")
    .replace(old="<sheetData/>", new="<sheetData>\{rows}</sheetData>")
  let bytes = @utf8.encode(worksheet)
  guard bytes.length() <= budget.entry_bytes else {
    @failure.reject(
      "limit-exceeded", "Chart snapshot worksheet exceeds entry budget",
    )
  }
  blank.opc.save(Map([(blank.sheets[0].id, bytes)]))
}
