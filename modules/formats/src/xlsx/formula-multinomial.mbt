///|
fn multinomial_function(
  args : Array[Expression],
  sheets : Array[Sheet],
  sheet : Int32,
  calculated : Map[(Int32, String), Value],
  work : FormulaWork,
  depth : Int32,
) -> Value raise @failure.Failure {
  let mut total = 0.0
  let mut denominator = 1.0
  for arg in args {
    let values = if arg is Reference(_, _, Some(_)) &&
      arg.aggregate_range(sheets, sheet) is Some(range) {
      aggregate_offsets([range], sheets, work).map(offset => {
        range.value(offset, sheets, calculated, work)
      })
    } else {
      [arg.evaluate(sheets, sheet, calculated, work, depth + 1)]
    }
    for value in values {
      work.spend()
      if value is Text(text) {
        work.spend(amount=text.length())
        // The native scalar-reference branch compares its raw value before checking type.
        if arg is Reference(_, _, None) {
          let text = text.trim()
          let decimal = text
            .iter()
            .all(c => {
              (c >= '0' && c <= '9') || ['+', '-', '.', 'E', 'e'].contains(c)
            })
          let negative = text == "-Infinity" ||
            (
              decimal &&
              text.has_prefix("-") &&
              ((@string.parse_double(text) < 0) catch {
                Failure("value out of range") => true
                _ => false
              })
            )
          if negative {
            return Error("#NUM!")
          }
        }
      }
      let number = match value {
        Number(number) => number
        Error(_) => return value
        _ => return Error("#VALUE!")
      }
      if number < 0 {
        return Error("#NUM!")
      }
      total += number
      if number.floor() <= 170 {
        denominator *= factorial_product(number, 1, work)
      }
    }
    if total.is_inf() || total.is_nan() {
      return Error("#VALUE!")
    }
  }
  if total > 170 {
    return Error("#VALUE!")
  }
  finite_result(factorial_product(total, 1, work) / denominator)
}
