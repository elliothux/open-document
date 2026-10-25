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
  for reference in [chart.categories] + chart.names + chart.values {
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
      guard cell.map(cell => cell.calculation_supported).unwrap_or(true) else {
        @failure.reject(
          "unsupported-chart",
          "Chart cell value requires support: " + name,
        )
      }
      let calculated = self.calculation.bind(c => c.values.get((index, name)))
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
