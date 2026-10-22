///|
fn Session::chart_visible_indices(
  self : Session,
  owner : String,
  formula : String,
  cached : Int,
  work : FormulaWork,
) -> Array[Int] raise @failure.Failure {
  if broken_chart_reference(formula) {
    return Array::makei(cached, index => index)
  }
  let (index, range) = self.chart_reference_range(formula, owner, work)
  let sheet = self.sheets[index]
  let count = range.bottom - range.top + range.right - range.left + 1
  Array::makei(count, index => index).filter(index => {
    sheet.dimensions.rows.size(
      range.top + (if range.top == range.bottom { 0 } else { index }),
    ) >
    0 &&
    sheet.dimensions.columns.size(
      range.left + (if range.left == range.right { 0 } else { index }),
    ) >
    0
  })
}

///|
fn Session::chart_visibility(
  self : Session,
  owner : String,
  chart : @chart.WorksheetChart,
) -> @layout.ChartVisibility raise @failure.Failure {
  let work : FormulaWork = {
    remaining: 1048576,
    date1904: self.date1904,
    origin: { row: 1, column: 1, },
    names: self.formula_names(),
  }
  {
    categories: self.chart_visible_indices(
      owner,
      chart.categories,
      chart.data.categories.length(),
      work,
    ),
    values: chart.values.mapi((index, formula) => {
      self.chart_visible_indices(
        owner,
        formula,
        chart.data.series[index].values.length(),
        work,
      )
    }),
    colors: chart.colors,
  }
}
