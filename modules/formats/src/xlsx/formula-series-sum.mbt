///|
fn series_sum_function(
  args : Array[Expression],
  sheets : Array[Sheet],
  sheet : Int32,
  calculated : Map[(Int32, String), Value],
  work : FormulaWork,
  depth : Int32,
) -> Value raise @failure.Failure {
  let parameters : Array[Double] = []
  for arg in args[:3] {
    let range = arg is Reference(_, _, Some(_))
    let value = arg.evaluate(sheets, sheet, calculated, work, depth + 1)
    if !range {
      if value is Blank {
        return Error("#N/A")
      }
      if value is Boolean(_) {
        return Error("#VALUE!")
      }
    }
    if value is Text(text) {
      work.spend(amount=text.length())
    }
    match (if value == Text("") { Number(0) } else { numeric_value(value) }) {
      Number(number) => parameters.push(number)
      error => return error
    }
  }
  let x = parameters[0]
  let n = parameters[1]
  let m = parameters[2]
  let coefficient = args[3]
  if coefficient is Reference(_, _, Some(_)) &&
    coefficient.aggregate_range(sheets, sheet) is Some(range) {
    let mut total = 0.0
    for offset in aggregate_offsets([range], sheets, work) {
      let value = range.value(offset, sheets, calculated, work)
      if value is Error(_) {
        return value
      }
      if value is Blank {
        return Error("#N/A")
      }
      if value is Boolean(_) {
        return Error("#VALUE!")
      }
      if value is Text(text) {
        work.spend(amount=text.length())
      }
      let number = match
        (if value == Text("") { Number(0) } else { numeric_value(value) }) {
        Number(number) => number
        _ => return Error("#VALUE!")
      }
      work.spend()
      let exponent = n + offset.to_double() * m
      let power = if x.abs() == 1 && exponent.is_inf() {
        0.0
      } else {
        @math.pow(x, exponent)
      }
      // Native range coefficients skip absent cells and replace NaN powers with zero.
      total += number * (if power.is_nan() { 0 } else { power })
    }
    return finite_result(total)
  }
  match coefficient.evaluate(sheets, sheet, calculated, work, depth + 1) {
    Number(number) => finite_result(number * @math.pow(x, n))
    Blank => Error("#N/A")
    _ => Error("#VALUE!")
  }
}
