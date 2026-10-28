///|
fn chart_range_reference(
  sheet : String,
  range : Range,
) -> String raise @failure.Failure {
  let first : FormulaAddress = {
    address: { row: range.top, column: range.left, },
    fixed_row: true,
    fixed_column: true,
  }
  let last : FormulaAddress = {
    address: { row: range.bottom, column: range.right, },
    fixed_row: true,
    fixed_column: true,
  }
  Expression::Reference(
    Some(sheet),
    first,
    if first == last {
      None
    } else {
      Some(last)
    },
  ).source()
}

///|
pub fn Session::insert_chart_range(
  self : Session,
  revision : Int32,
  sheet : String,
  source : String,
  kind : String,
  title : String,
  width : Double,
  height : Double,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let current = self.sheets[self.sheet_index(sheet)]
  let range = Range::parse(source)
  guard range.bottom > range.top &&
    range.bottom - range.top <= 256 &&
    range.right > range.left &&
    range.right - range.left <= 8 else {
    @failure.reject(
      "invalid-chart", "Chart range requires a header row, 1-256 data rows and 1-8 series",
    )
  }
  let settings : SheetChartSettings = {
    kind,
    title,
    label: "",
    legend: if ["pie", "doughnut"].contains(kind) {
      "right"
    } else {
      "bottom"
    },
    hole_size: if kind == "doughnut" {
      Some(75)
    } else {
      None
    },
    categories: chart_range_reference(current.name, {
      ..range,
      top: range.top + 1,
      right: range.left,
    }),
    names: Array::makei(range.right - range.left, offset => {
      chart_range_reference(current.name, {
        top: range.top,
        bottom: range.top,
        left: range.left + offset + 1,
        right: range.left + offset + 1,
      })
    }),
    values: Array::makei(range.right - range.left, offset => {
      chart_range_reference(current.name, {
        ..range,
        top: range.top + 1,
        left: range.left + offset + 1,
        right: range.left + offset + 1,
      })
    }),
  }
  self.insert_chart(revision, sheet, settings, width, height, probe, profile)
}
