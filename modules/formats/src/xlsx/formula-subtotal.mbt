///|
fn Expression::contains_subtotal(self : Expression) -> Bool {
  match self {
    Function("SUBTOTAL", _) => true
    Function(_, args) => args.any(arg => arg.contains_subtotal())
    Unary(_, value) => value.contains_subtotal()
    Binary(_, left, right) =>
      left.contains_subtotal() || right.contains_subtotal()
    _ => false
  }
}

///|
fn Calculation::visibility_dependent(self : Calculation) -> Bool {
  self.expressions.values().any(expression => expression.contains_subtotal())
}

///|
fn subtotal_filtered(
  sheet : Sheet,
  work : FormulaWork,
) -> Array[Int] raise @failure.Failure {
  work.spend(amount=sheet.document.nodes().length())
  let filters = work.names.tables
    .filter(table => table.sheet == sheet.id)
    .filter_map(table => table.filter)
  if read_filter(sheet) is Some(filter) {
    filters.push(filter)
  }
  // shortcut: Imported active filters have no separate hidden causes; tracked saves distinguish overlap.
  let result : Array[Int] = []
  for filter in filters {
    if filter.tracked {
      for row in filter.filtered {
        work.spend()
        if !result.contains(row) {
          result.push(row)
        }
      }
    } else if !filter.settings.columns.is_empty() {
      for row in (filter.bounds.top + 1)..<=filter.bounds.bottom {
        work.spend()
        if sheet.dimensions.rows.size(row) == 0 && !result.contains(row) {
          result.push(row)
        }
      }
    }
  }
  result
}

///|
fn subtotal_function(
  args : Array[Expression],
  sheets : Array[Sheet],
  sheet : Int,
  calculated : Map[(Int, String), Value],
  work : FormulaWork,
  depth : Int,
) -> Value raise @failure.Failure {
  let selector = numeric_value(
    args[0].evaluate(sheets, sheet, calculated, work, depth + 1),
  )
  if selector is Error(_) {
    return selector
  }
  guard selector is Number(selector) &&
    ((selector >= 1 && selector <= 11) || (selector >= 101 && selector <= 111)) &&
    selector.to_int().to_double() == selector else {
    return Error("#VALUE!")
  }
  let exclude_manual = selector >= 100
  let kind = selector.to_int() % 100
  let items : Array[(Value, Bool)] = []
  let hidden : Map[Int, Array[Int]] = Map([])
  for arg in args[1:] {
    if arg.aggregate_range(sheets, sheet) is Some(range) {
      if !exclude_manual && !hidden.contains(range.sheet) {
        hidden[range.sheet] = subtotal_filtered(sheets[range.sheet], work)
      }
      for offset in aggregate_offsets([range], sheets, work) {
        let width = (range.bounds.right - range.bounds.left + 1).to_int64()
        let address : Address = {
          row: range.bounds.top + (offset / width).to_int(),
          column: range.bounds.left + (offset % width).to_int(),
        }
        if (
            exclude_manual &&
            sheets[range.sheet].dimensions.rows.size(address.row) == 0
          ) ||
          hidden.get(range.sheet).unwrap_or([]).contains(address.row) {
          continue
        }
        if sheets[range.sheet].cells
          .get(address.name())
          .bind(cell => cell.formula)
          is Some(source) {
          work.spend(amount=source.length())
          if parse_formula(source)
            .resolve_names(sheets, range.sheet, address, work)
            .contains_subtotal() {
            continue
          }
        }
        items.push((range.value(offset, sheets, calculated, work), true))
      }
    } else {
      let value = arg.evaluate(sheets, sheet, calculated, work, depth + 1)
      if value is Error(_) {
        return value
      }
      items.push((value, false))
    }
  }
  let numbers : Array[Double] = []
  let mut occupied = 0
  for (value, reference) in items {
    work.spend()
    if value != Blank {
      occupied += 1
    }
    if kind == 3 {
      continue
    }
    let numeric_text = reference && kind == 6 && value is Text(_)
    let value = if reference {
      if kind == 6 && value is Text(_) {
        numeric_value(value)
      } else {
        value
      }
    } else {
      numeric_value(value)
    }
    match value {
      Number(number) => numbers.push(number)
      Error(error) if kind != 2 => {
        // Numeric text in referenced PRODUCT cells is accepted; other text is ignored.
        if numeric_text {
          continue
        }
        return Error(error)
      }
      _ => ()
    }
  }
  if kind == 3 {
    return Number(occupied.to_double())
  }
  if kind == 2 {
    return Number(numbers.length().to_double())
  }
  let count = numbers.length()
  if count == 0 {
    return if [1, 7, 8, 10, 11].contains(kind) {
      Error("#DIV/0!")
    } else {
      Number(0)
    }
  }
  let mut sum = 0.0
  let mut product = 1.0
  let mut minimum = numbers[0]
  let mut maximum = minimum
  let mut mean = 0.0
  let mut squared = 0.0
  for index, number in numbers {
    work.spend()
    sum += number
    product *= number
    minimum = minimum.min(number)
    maximum = maximum.max(number)
    let delta = number - mean
    mean += delta / (index + 1).to_double()
    squared += delta * (number - mean)
  }
  match kind {
    1 => finite_result(sum / count.to_double())
    4 => Number(maximum)
    5 => Number(minimum)
    6 => finite_result(product)
    9 => finite_result(sum)
    _ => {
      let sample = kind == 7 || kind == 10
      if sample && count < 2 {
        return Error("#DIV/0!")
      }
      let divisor = if sample { count - 1 } else { count }
      if squared.is_nan() || squared.is_inf() {
        return Error("#NUM!")
      }
      let variance = squared.max(0) / divisor.to_double()
      finite_result(
        if kind == 7 || kind == 8 {
          variance.sqrt()
        } else {
          variance
        },
      )
    }
  }
}
