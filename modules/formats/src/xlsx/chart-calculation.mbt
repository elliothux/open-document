///|
let uncalculated_chart_reason = "Chart formulas are uncalculated; imported cached values are shown"

///|
fn Session::chart_input_state(
  self : Session,
  owner : String,
  chart : @chart.WorksheetChart,
  work : FormulaWork,
) -> (Bool, Array[(String, String, Value, String?, Bool, Bool)]) raise @failure.Failure {
  let mut pending = false
  let inputs = []
  for reference in chart_references(chart) {
    if broken_chart_reference(reference) {
      continue
    }
    let (index, range) = self.chart_reference_range(reference, owner, work)
    let sheet = self.sheets[index]
    for offset in 0..<(range.bottom - range.top + range.right - range.left + 1) {
      let address : Address = {
        row: range.top + (if range.top == range.bottom { 0 } else { offset }),
        column: range.left +
        (if range.left == range.right { 0 } else { offset }),
      }
      let name = address.name()
      let cell = sheet.cells.get(name)
      if !cell.map(cell => cell.calculation_supported).unwrap_or(true) {
        pending = true
      }
      let calculated = self.calculation.bind(c => c.values.get((index, name)))
      if cell.bind(cell => cell.formula) is Some(_) && calculated is None {
        pending = true
      }
      if self.calculation
        .map(c => c.uncomputed.contains((index, name)))
        .unwrap_or(false) {
        pending = true
      }
      inputs.push(
        (
          sheet.id,
          name,
          calculated.unwrap_or(cell.map(cell => cell.value).unwrap_or(Blank)),
          cell.bind(cell => cell.formula),
          sheet.dimensions.rows.size(address.row) == 0,
          sheet.dimensions.columns.size(address.column) == 0,
        ),
      )
    }
  }
  (pending, inputs)
}

///|
fn Session::manual_chart_error_gaps(
  self : Session,
  owner : String,
  chart : @chart.WorksheetChart,
  work : FormulaWork,
) -> @chart.WorksheetChart raise @failure.Failure {
  let series = chart.data.series.mapi((index, series) => {
    let source = chart.values[index]
    if !series.values.contains(Some(0.0)) || broken_chart_reference(source) {
      return series
    }
    let cells = self.chart_reference_values(source, owner, work)
    // A cached zero can stand for a source error. Keep actual zeros and other cached numbers.
    let values = series.values.mapi((point, value) => {
      if value == Some(0.0) && cells.get(point) is Some(Error(_)) {
        None
      } else {
        value
      }
    })
    { ..series, values, }
  })
  { ..chart, data: { ..chart.data, series, }, }
}
