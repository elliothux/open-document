///|
let chart_uri = "http://schemas.openxmlformats.org/drawingml/2006/chart"

///|
priv struct ChartSeries {
  name : String
  values : Array[Double?]
} derive(Eq)

///|
priv struct ChartData {
  kind : String
  title : String
  label : String
  categories : Array[String]
  series : Array[ChartSeries]
} derive(Eq)

///|
priv struct DrawingChart {
  part : String
  workbook : String
  data : ChartData
}

///|
fn chart_text(text : String) -> Unit raise @failure.Failure {
  guard text.length() <= 256 &&
    @xml.valid_text(text) &&
    !text.contains("\n") &&
    !text.contains("\r") else {
    @failure.reject(
      "invalid-chart", "Chart labels require at most 256 plain characters",
    )
  }
}

///|
fn ChartData::validate(self : ChartData) -> Unit raise @failure.Failure {
  guard ["column", "bar", "line", "pie"].contains(self.kind) &&
    self.categories.length() >= 1 &&
    self.categories.length() <= 256 &&
    self.series.length() >= 1 &&
    self.series.length() <= 8 else {
    @failure.reject(
      "limit-exceeded", "Chart requires 1-256 categories and 1-8 series",
    )
  }
  chart_text(self.title)
  chart_text(self.label)
  for category in self.categories {
    chart_text(category)
  }
  for series in self.series {
    chart_text(series.name)
    guard !series.name.is_empty() &&
      series.values.length() == self.categories.length() &&
      series.values.all(value => {
        value.map(v => !v.is_nan() && !v.is_inf()).unwrap_or(true)
      }) else {
      @failure.reject(
        "invalid-chart", "Chart series must match categories and contain finite numbers or blanks",
      )
    }
  }
}

///|
fn chart_data(
  kind : String,
  title : String,
  bytes : Bytes,
  budget : @archive.Budget,
) -> ChartData raise @failure.Failure {
  let workbook = @xlsx.Session::open(bytes, budget)
  defer workbook.close()
  guard workbook.query(range=Some("A1:XFD1048576"))
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
  let result : ChartData = {
    kind,
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
fn ChartData::tsv(self : ChartData) -> String {
  let quote = fn(text : String) {
    "\"" + text.replace_all(old="\"", new="\"\"") + "\""
  }
  let rows = [
    ([self.label] + self.series.map(series => series.name))
    .map(quote)
    .join("\t"),
  ]
  for index, category in self.categories {
    rows.push(
      ([category] +
      self.series.map(series => {
        series.values[index].map(value => value.to_string()).unwrap_or("")
      }))
      .map(quote)
      .join("\t"),
    )
  }
  rows.join("\n")
}

///|
fn ChartData::query(self : ChartData) -> Json {
  { "kind": self.kind, "title": self.title, "data": self.tsv() }
}

///|
fn chart_color(index : Int) -> String {
  [
    "4472c4", "ed7d31", "a5a5a5", "ffc000", "5b9bd5", "70ad47", "264478", "9e480e",
  ][index % 8]
}

///|
fn ChartData::axis(
  self : ChartData,
) -> (Double, Double, Double) raise @failure.Failure {
  let mut low = 0.0
  let mut high = 0.0
  for series in self.series {
    for value in series.values {
      if value is Some(value) {
        low = low.min(value)
        high = high.max(value)
      }
    }
  }
  if low == high {
    return (0, 1, 0.2)
  }
  let rough = (high - low) / 5
  guard rough > 0 && !rough.is_inf() else {
    @failure.reject(
      "limit-exceeded", "Chart value range exceeds numeric precision",
    )
  }
  let mut unit = 1.0
  while unit * 10 <= rough {
    unit *= 10
  }
  while unit > rough {
    unit /= 10
    guard unit > 0 else {
      @failure.reject(
        "limit-exceeded", "Chart interval underflows numeric precision",
      )
    }
  }
  let ratio = rough / unit
  let step = unit *
    (if ratio <= 1 {
      1.0
    } else if ratio <= 2 {
      2.0
    } else if ratio <= 5 {
      5.0
    } else {
      10.0
    })
  low = (low / step).floor() * step
  high = (high / step).ceil() * step
  guard !low.is_inf() && !high.is_inf() && !(high - low).is_inf() && high > low else {
    @failure.reject("limit-exceeded", "Chart axis exceeds numeric limits")
  }
  (low, high, step)
}
