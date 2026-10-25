///|
fn isolated_math_function(name : String) -> Bool {
  // These built-ins read only explicit arguments; dynamic and user functions stay global.
  ["ACOSH", "ASINH", "ATANH"].contains(name)
}

///|
fn Calculation::protect_dependencies(
  self : Calculation,
  formulas : Map[Int, Array[(Int, String)]],
  work : FormulaWork,
) -> Unit raise @failure.Failure {
  if self.uncomputed.is_empty() {
    return
  }
  let guarded = Set::from_array(self.uncomputed.keys().to_array())
  let mut count = 0
  fn add_range(sheet : Int, range : Range) -> Unit raise @failure.Failure {
    let ranges = self.guarded_ranges
      .get(sheet)
      .unwrap_or_else(() => {
        let ranges : Array[Range] = []
        self.guarded_ranges[sheet] = ranges
        ranges
      })
    work.spend(amount=ranges.length() + 1)
    if !ranges.contains(range) {
      count += 1
      guard count <= 4096 else {
        @failure.reject(
          "unsupported-formula", "Uncalculated dependency protection exceeds4096 ranges",
        )
      }
      ranges.push(range)
    }
  }
  for key in self.order.rev() {
    guard guarded.contains(key) else { continue }
    let address = Address::parse(key.1)
    add_range(key.0, {
      top: address.row,
      bottom: address.row,
      left: address.column,
      right: address.column,
    })
    if self.expressions[key].contains_subtotal() {
      self.protected_visibility = true
    }
    for dependency in self.dependencies[key] {
      add_range(dependency.sheet, dependency.range)
      for candidate in formulas.get(dependency.sheet).unwrap_or([]) {
        work.spend()
        if dependency.range.contains(Address::parse(candidate.1)) {
          guarded.add(candidate)
        }
      }
    }
  }
}

///|
fn Calculation::protects(
  self : Calculation,
  sheet : Int,
  address : Address,
) -> Bool {
  self.guarded_ranges
  .get(sheet)
  .map(ranges => ranges.any(range => range.contains(address)))
  .unwrap_or(false)
}

///|
fn Session::cell_calculation_reason(
  self : Session,
  sheet : Int,
  address : String,
) -> String {
  if !self.read_only.is_empty() {
    return self.read_only
  }
  self.calculation
  .bind(calculation => calculation.uncomputed.get((sheet, address)))
  .unwrap_or("")
}

///|
fn Session::check_partial_calculation(
  self : Session,
  sheets : Array[Sheet],
  calculation : Calculation,
) -> Unit raise @failure.Failure {
  if calculation.uncomputed.is_empty() {
    return
  }
  guard self.calculation is Some(previous) &&
    sheets.map(sheet => (sheet.id, sheet.name)) ==
    self.sheets.map(sheet => (sheet.id, sheet.name)) else {
    @failure.reject(
      "protected-content", "Uncalculated formulas require stable worksheet identities",
    )
  }
  for key in calculation.uncomputed.keys() {
    guard previous.uncomputed.contains(key) &&
      previous.sources.get(key) == calculation.sources.get(key) &&
      previous.expressions.get(key) == calculation.expressions.get(key) else {
      @failure.reject(
        "protected-content", "An uncalculated formula or its references changed",
      )
    }
  }
  let before_work : FormulaWork = {
    remaining: 1048576,
    date1904: self.date1904,
    origin: { row: 1, column: 1, },
    names: previous.names,
  }
  let after_work = { ..before_work, names: calculation.names, }
  for index in calculation.guarded_ranges.keys() {
    let before = self.sheets[index]
    let after = sheets[index]
    let filtered_before = if calculation.protected_visibility {
      subtotal_filtered(before, before_work)
    } else {
      []
    }
    let filtered_after = if calculation.protected_visibility {
      subtotal_filtered(after, after_work)
    } else {
      []
    }
    let keys = Set::from_array(
      before.cells.keys().to_array() + after.cells.keys().to_array(),
    )
    for key in keys {
      before_work.spend(amount=calculation.guarded_ranges[index].length() + 1)
      let address = Address::parse(key)
      guard calculation.protects(index, address) else { continue }
      let original = before.cells.get(key)
      let next = after.cells.get(key)
      let a = previous.values
        .get((index, key))
        .unwrap_or(original.map(cell => cell.value).unwrap_or(Blank))
      let b = calculation.values
        .get((index, key))
        .unwrap_or(next.map(cell => cell.value).unwrap_or(Blank))
      guard a == b &&
        original.bind(cell => cell.formula) == next.bind(cell => cell.formula) &&
        (
          !calculation.protected_visibility ||
          (
            (before.dimensions.rows.size(address.row) == 0) ==
            (after.dimensions.rows.size(address.row) == 0) &&
            filtered_before.contains(address.row) ==
            filtered_after.contains(address.row)
          )
        ) else {
        @failure.reject(
          "protected-content", "Change affects an uncalculated formula",
        )
      }
    }
  }
}
