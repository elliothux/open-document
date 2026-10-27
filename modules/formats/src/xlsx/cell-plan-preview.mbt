///|
fn Session::cell_plan_values(
  self : Session,
  sheet : String,
  target : Range,
  edit : CellEditPlan,
) -> Array[Array[String]] raise @failure.Failure {
  let index = self.sheet_index(sheet)
  let candidate : Session = {
    ..self,
    sheets: edit.sheets,
    styles: edit.styles,
    parts: edit.parts,
    calculation: Some(edit.calculation),
  }
  let work : FormulaWork = {
    remaining: 1048576,
    date1904: self.date1904,
    origin: { row: target.top, column: target.left, },
    names: edit.calculation.names,
  }
  let rules = candidate.filter_rules(index, work)
  let result : Array[Array[String]] = []
  for row in target.top..<=target.bottom.min(target.top + 9) {
    let values : Array[String] = []
    for column in target.left..<=target.right {
      let address : Address = { row, column, }
      let style = rules.applied(
        edit.styles[edit.sheets[index].style_at(address)],
        address,
        edit.sheets,
        index,
        edit.calculation.values,
        work,
      )
      guard style.diagnostic.is_empty() else {
        @failure.reject("protected-content", style.diagnostic)
      }
      let value = formatted(
        candidate.filter_raw(index, row, column),
        style.format,
        self.date1904,
      )
      work.spend(amount=value.length() + 1)
      values.push(value)
    }
    result.push(values)
  }
  result
}
