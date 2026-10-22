///|
pub fn stacked_chart(kind : String) -> Bool {
  ["stackedColumn", "stackedBar"].contains(kind) || percent_stacked_chart(kind)
}

///|
pub fn percent_stacked_chart(kind : String) -> Bool {
  ["percentStackedColumn", "percentStackedBar"].contains(kind)
}

///|
pub fn horizontal_bar_chart(kind : String) -> Bool {
  ["bar", "stackedBar", "percentStackedBar"].contains(kind)
}

///|
pub(all) struct ChartSeries {
  name : String
  values : Array[Double?]
} derive(Eq)

///|
pub extend ChartSeries with Eq::{equal, not_equal}

///|
pub(all) struct ChartData {
  kind : String
  hole_size : Int?
  legend : String
  title : String
  label : String
  categories : Array[String]
  series : Array[ChartSeries]
} derive(Eq)

///|
pub extend ChartData with Eq::{equal, not_equal}

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
pub fn ChartData::validate(self : ChartData) -> Unit raise @failure.Failure {
  self.validate_sources()
  guard !self.categories.is_empty() &&
    self.series.all(series => series.values.length() == self.categories.length()) else {
    @failure.reject(
      "invalid-chart", "Chart series must match nonempty categories",
    )
  }
}

///|
/// Validate independently cached sources before normalizing them for plotting.
pub fn ChartData::validate_sources(
  self : ChartData,
) -> Unit raise @failure.Failure {
  guard ["none", "top", "bottom", "left", "right"].contains(self.legend) else {
    @failure.reject("invalid-chart", "Unsupported chart legend position")
  }
  guard [
      "column", "bar", "stackedColumn", "stackedBar", "line", "pie", "area", "scatter",
      "doughnut", "percentStackedColumn", "percentStackedBar", "radar",
    ].contains(self.kind) &&
    self.categories.length() <= 256 &&
    self.series.length() >= 1 &&
    self.series.length() <= 8 else {
    @failure.reject(
      "limit-exceeded", "Chart sources require at most 256 points and 1-8 series",
    )
  }
  guard (if self.kind == "doughnut" {
    self.hole_size.map(size => size >= 10 && size <= 90).unwrap_or(false)
  } else {
    self.hole_size is None
  }) else {
    @failure.reject(
      "invalid-chart", "Doughnut hole size requires an integer from 10 to 90",
    )
  }
  chart_text(self.title)
  chart_text(self.label)
  for category in self.categories {
    chart_text(category)
  }
  if self.kind == "scatter" {
    ignore(self.scatter_values())
  }
  for series in self.series {
    chart_text(series.name)
    guard !series.name.is_empty() &&
      series.values.length() <= 256 &&
      series.values.all(value => {
        value.map(v => !v.is_nan() && !v.is_inf()).unwrap_or(true)
      }) else {
      @failure.reject(
        "invalid-chart", "Chart series require finite numbers or blanks",
      )
    }
  }
  guard self.tsv().length() <= 65536 else {
    @failure.reject(
      "limit-exceeded", "Canonical chart data exceeds 65536 characters",
    )
  }
}

///|
pub fn ChartData::tsv(self : ChartData) -> String {
  let quote = fn(text : String) {
    "\"" + text.replace_all(old="\"", new="\"\"") + "\""
  }
  let rows = [
    ([self.label] + self.series.map(series => series.name))
    .map(quote)
    .join("\t"),
  ]
  let count = self.series.fold(init=self.categories.length(), (count, series) => {
    count.max(series.values.length())
  })
  for index in 0..<count {
    let category = self.categories
      .get(index)
      .unwrap_or(
        if self.kind == "scatter" {
          ""
        } else {
          (index + 1).to_string()
        },
      )
    rows.push(
      ([category] +
      self.series.map(series => {
        series.values
        .get(index)
        .bind(value => value)
        .map(value => value.to_string())
        .unwrap_or("")
      }))
      .map(quote)
      .join("\t"),
    )
  }
  rows.join("\n")
}

///|
pub fn ChartData::query(self : ChartData) -> Json {
  let fields : Map[String, Json] = {
    "kind": Json(self.kind),
    "title": Json(self.title),
    "data": Json(self.tsv()),
    "legend": Json(self.legend),
  }
  if self.hole_size is Some(size) {
    fields["holeSize"] = Json(size)
  }
  Json(fields)
}

///|
pub fn chart_color(index : Int) -> String {
  [
    "4472c4", "ed7d31", "a5a5a5", "ffc000", "5b9bd5", "70ad47", "264478", "9e480e",
  ][index % 8]
}

///|
pub fn ChartData::bar_values(self : ChartData, index : Int) -> Array[Double?] {
  let values = self.series.map(series => series.values[index])
  if !percent_stacked_chart(self.kind) {
    return values
  }
  let scale = values.fold(init=0.0, (maximum, value) => {
    maximum.max(value.unwrap_or(0).abs())
  })
  if scale == 0 {
    return values
  }
  // Normalize before summing so finite source values cannot overflow a percentage total.
  let total = values.fold(init=0.0, (sum, value) => {
    sum + value.unwrap_or(0).abs() / scale
  })
  values.map(value => value.map(value => value / scale / total))
}

///|
pub fn ChartData::axis(
  self : ChartData,
) -> (Double, Double, Double) raise @failure.Failure {
  let mut low = 0.0
  let mut high = 0.0
  let stacked = stacked_chart(self.kind)
  for index in 0..<self.categories.length() {
    let mut positive = 0.0
    let mut negative = 0.0
    for value in self.bar_values(index) {
      if value is Some(value) {
        if stacked {
          positive += value.max(0)
          negative += value.min(0)
        } else {
          low = low.min(value)
          high = high.max(value)
        }
      }
    }
    guard !positive.is_inf() && !negative.is_inf() else {
      @failure.reject("limit-exceeded", "Chart stack exceeds numeric limits")
    }
    low = low.min(negative)
    high = high.max(positive)
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
  if percent_stacked_chart(self.kind) {
    low = low.max(-1)
    high = high.min(1)
  }
  guard !low.is_inf() && !high.is_inf() && !(high - low).is_inf() && high > low else {
    @failure.reject("limit-exceeded", "Chart axis exceeds numeric limits")
  }
  (low, high, step)
}
