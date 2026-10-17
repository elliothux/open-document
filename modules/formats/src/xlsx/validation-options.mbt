///|
fn validation_values(
  expression : Expression,
  sheets : Array[Sheet],
  sheet : Int,
  calculation : Calculation,
  work : FormulaWork,
) -> Array[Value] raise @failure.Failure {
  let values : Array[Value] = []
  if expression is Constant(Text(text)) {
    for item in text.split(",") {
      work.spend()
      let mut start = 0
      while start < item.length() && item[start] == 32 {
        start += 1
      }
      values.push(Text(item[start:].to_owned()))
      guard values.length() <= 4096 else {
        @failure.reject(
          "limit-exceeded", "Validation list exceeds 4096 entries",
        )
      }
    }
  } else {
    guard expression.aggregate_range(sheets, sheet) is Some(range) &&
      (
        range.bounds.left == range.bounds.right ||
        range.bounds.top == range.bounds.bottom
      ) else {
      @failure.reject(
        "protected-content", "Validation list requires a literal list or one row or column reference",
      )
    }
    guard range.area() <= 4096L else {
      @failure.reject(
        "limit-exceeded", "Validation list range exceeds 4096 cells",
      )
    }
    for offset = 0L; offset < range.area(); offset = offset + 1 {
      values.push(range.value(offset, sheets, calculation.values, work))
    }
  }
  let mut units = 0
  for value in values {
    units += value.display().length()
    guard units <= 1048576 else {
      @failure.reject("limit-exceeded", "Validation list text exceeds budget")
    }
  }
  values
}

///|
fn Session::validation_options(
  self : Session,
  sheet : Int,
  range : Range,
  rule : DataValidation,
) -> Array[Value] raise @failure.Failure {
  let address : Address = { row: range.top, column: range.left, }
  let reason = self.dimension_reason(self.sheets[sheet])
  guard reason.is_empty() &&
    self.sheets[sheet].cells
    .get(address.name())
    .map(c => c.read_only.is_empty())
    .unwrap_or(true) else {
    @failure.reject("protected-content", "Cell input is protected")
  }
  guard range == self.sheets[sheet].cell_range(address) else {
    @failure.reject(
      "invalid-operation", "Select one cell to use the validation list",
    )
  }
  guard rule.kind == "list" && !rule.showDropDown else {
    @failure.reject("invalid-operation", "Validation list dropdown is disabled")
  }
  let work = FormulaWork::{
    remaining: 1048576,
    date1904: self.date1904,
    origin: address,
    names: self.formula_names(),
  }
  let expression = rule_expression(
    rule.formula1,
    address,
    address,
    self.sheets,
    sheet,
    work,
  )
  validation_values(
    expression,
    self.sheets,
    sheet,
    self.calculation.unwrap(),
    work,
  )
}

///|
fn Session::pick_validation(
  self : Session,
  id : String,
  index : Int,
  source_revision : Int,
) -> Json raise @failure.Failure {
  self.check_revision(source_revision)
  guard id == self.selection.0 else {
    @failure.reject("invalid-operation", "Validation list selection changed")
  }
  let sheet = self.sheet_index(id)
  let range = self.selection.1
  let (rule, mixed) = self.sheets[sheet].validation_at(range)
  guard !mixed && rule is Some(rule) else {
    @failure.reject(
      "invalid-operation", "Select a cell with one validation list",
    )
  }
  let values = self.validation_options(sheet, range, rule)
  guard index >= 0 && values.get(index) is Some(value) else {
    @failure.reject("invalid-operation", "Invalid validation list option")
  }
  let address : Address = { row: range.top, column: range.left, }
  guard !self.sheets[sheet].locked &&
    self.sheets[sheet].cells
    .get(address.name())
    .map(cell => cell.read_only.is_empty())
    .unwrap_or(true) else {
    @failure.reject("protected-content", "Cell input is protected")
  }
  let current = self.sheets[sheet].cells.get(address.name())
  if current.map(c => c.value).unwrap_or(Blank) == value &&
    current.bind(c => c.formula) is None {
    return self.query()
  }
  self.commit_cells(
    Map([
      (
        sheet,
        Map([(address.name(), { value, formula: None, keep_shared: false, })]),
      ),
    ]),
    self.selection,
  )
}
