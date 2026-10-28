///|
fn sum_squares_function(
  args : Array[Expression],
  sheets : Array[Sheet],
  sheet : Int32,
  calculated : Map[(Int32, String), Value],
  work : FormulaWork,
  depth : Int32,
) -> Value raise @failure.Failure {
  let mut total = 0.0
  for arg in args {
    if arg.aggregate_range(sheets, sheet) is Some(range) {
      for offset in aggregate_offsets([range], sheets, work) {
        match range.value(offset, sheets, calculated, work) {
          Number(number) => total += number * number
          // ONLYOFFICE ignores errors in single references, but propagates range errors.
          Error(_) as error if !(arg is Reference(_, _, None)) => return error
          _ => ()
        }
      }
    } else {
      let value = arg.evaluate(sheets, sheet, calculated, work, depth + 1)
      if value is Text(text) {
        work.spend(amount=text.length())
      }
      match numeric_value(value) {
        Number(number) => total += number * number
        Error(_) as error => return error
        _ => abort("Expected numeric aggregate value")
      }
    }
    if total.is_nan() || total.is_inf() {
      return Error("#NUM!")
    }
  }
  Number(total)
}
