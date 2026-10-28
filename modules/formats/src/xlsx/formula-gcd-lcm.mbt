///|
fn integer_gcd(
  left : Double,
  right : Double,
  work : FormulaWork,
) -> Double raise @failure.Failure {
  let mut left = left.trunc()
  let mut right = right.trunc()
  while right != 0 {
    work.spend()
    let remainder = left % right
    left = right
    right = remainder
  }
  left
}

///|
fn factor_function(
  name : String,
  args : Array[Expression],
  sheets : Array[Sheet],
  sheet : Int32,
  calculated : Map[(Int32, String), Value],
  work : FormulaWork,
  depth : Int32,
) -> Value raise @failure.Failure {
  let gcd = name == "GCD"
  let mut result = if gcd { 0.0 } else { 1.0 }
  for arg in args {
    let range = match arg {
      Reference(_, _, Some(_)) => arg.aggregate_range(sheets, sheet)
      _ => None
    }
    let scalar_reference = arg is Reference(_, _, None)
    let values = if range is Some(range) {
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
      }
      let value = match value {
        Boolean(_) if !scalar_reference => return Error("#VALUE!")
        Blank if !scalar_reference =>
          if gcd {
            return Error("#N/A")
          } else {
            Number(1)
          }
        _ => numeric_value(value)
      }
      guard value is Number(number) else { return value }
      let limit = 9007199254740992.0
      if number < 0 ||
        number > limit ||
        (gcd && range is None && number == limit) {
        return Error("#NUM!")
      }
      if gcd {
        result = integer_gcd(result, number, work)
      } else {
        if number < 1 && range is None {
          return Number(0)
        }
        // ONLYOFFICE applies JavaScript parseInt to the accumulated LCM.
        let left = if result >= 1.0e21 {
          @string.parse_double(result.to_string().split("e").head().unwrap()) catch {
            _ => return Error("#NUM!")
          }
        } else {
          result
        }
        if !left.is_nan() {
          let left = left.trunc()
          let right = number.trunc()
          result = left * right / integer_gcd(left, right, work)
        }
      }
    }
  }
  finite_result(result)
}
