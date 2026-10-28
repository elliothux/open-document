///|
fn Session::chart_visible_indices(
  self : Session,
  owner : String,
  formula : String,
  cached : Int32,
  work : FormulaWork,
  cached_only~ : Bool = false,
) -> Array[Int32] raise @failure.Failure {
  if broken_chart_reference(formula) {
    return Array::makei(cached, index => index)
  }
  let (index, range) = self.chart_reference_range(formula, owner, work)
  let sheet = self.sheets[index]
  let count = range.bottom - range.top + range.right - range.left + 1
  guard !cached_only || count == cached else {
    @failure.reject(
      "unsupported-chart", "Uncalculated chart cache does not match its source range",
    )
  }
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
  cached_only~ : Bool = false,
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
      cached_only~,
    ),
    values: chart.values.mapi((index, formula) => {
      self.chart_visible_indices(
        owner,
        formula,
        chart.data.series[index].values.length(),
        work,
        cached_only~,
      )
    }),
    colors: chart.colors,
  }
}
