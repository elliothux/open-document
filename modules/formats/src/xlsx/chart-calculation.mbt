///|
let uncalculated_chart_reason = "Chart formulas are uncalculated; imported cached values are shown"

///|
priv struct ChartInput {
  sheet : String
  address : Address
  value : Value
  formula : String?
  hidden_row : Bool
  hidden_column : Bool
} derive(Eq)

///|
priv struct ChartInputs {
  pending : Bool
  has_formula : Bool
  has_error : Bool
  references : Map[String, Array[ChartInput]]
} derive(Eq)

///|
fn Session::chart_input_state(
  self : Session,
  owner : String,
  chart : @chart.WorksheetChart,
  work : FormulaWork,
) -> ChartInputs raise @failure.Failure {
  let mut pending = false
  let mut has_formula = false
  let mut has_error = false
  let references : Map[String, Array[ChartInput]] = Map([])
  for reference in chart_references(chart) {
    if broken_chart_reference(reference) {
      continue
    }
    if references.get(reference) is Some(cells) {
      work.spend(amount=cells.length())
      continue
    }
    let (index, range) = self.chart_reference_range(reference, owner, work)
    let sheet = self.sheets[index]
    let inputs : Array[ChartInput] = []
    for offset in 0..<(range.bottom - range.top + range.right - range.left + 1) {
      let address : Address = {
        row: range.top + (if range.top == range.bottom { 0 } else { offset }),
        column: range.left +
        (if range.left == range.right { 0 } else { offset }),
      }
      let cell = sheet.cells.get(address.name())
      if !cell.map(cell => cell.calculation_supported).unwrap_or(true) {
        pending = true
      }
      let calculated = self.calculation.bind(c => c.values.get((index, address)))
      let formula = cell.bind(cell => cell.formula)
      if formula is Some(_) && calculated is None {
        pending = true
      }
      if self.calculation
        .map(c => c.uncomputed.contains((index, address)))
        .unwrap_or(false) {
        pending = true
      }
      let value = calculated.unwrap_or(
        cell.map(cell => cell.value).unwrap_or(Blank),
      )
      has_formula = has_formula || formula is Some(_)
      has_error = has_error || value is Error(_)
      inputs.push({
        sheet: sheet.id,
        address,
        value,
        formula,
        hidden_row: sheet.dimensions.rows.size(address.row) == 0,
        hidden_column: sheet.dimensions.columns.size(address.column) == 0,
      })
    }
    references[reference] = inputs
  }
  { pending, has_formula, has_error, references, }
}

///|
fn Session::manual_chart_error_gaps(
  self : Session,
  owner : String,
  chart : @chart.WorksheetChart,
  work : FormulaWork,
  inputs : ChartInputs,
) -> @chart.WorksheetChart raise @failure.Failure {
  let series = chart.data.series.mapi((index, series) => {
    let source = chart.values[index]
    if !series.values.contains(Some(0.0)) || broken_chart_reference(source) {
      return series
    }
    let cells = self.chart_reference_values(
      source,
      owner,
      work,
      inputs=Some(inputs),
    )
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
