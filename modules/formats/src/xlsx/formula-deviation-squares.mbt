///|
fn deviation_squares_function(
  args : Array[Expression],
  sheets : Array[Sheet],
  sheet : Int,
  calculated : Map[(Int, String), Value],
  work : FormulaWork,
  depth : Int,
) -> Value raise @failure.Failure {
  let numbers : Array[Double] = []
  for arg in args {
    if arg.aggregate_range(sheets, sheet) is Some(range) {
      for offset in aggregate_offsets([range], sheets, work) {
        if range.value(offset, sheets, calculated, work) is Number(number) {
          numbers.push(number)
        }
      }
    } else {
      match arg.evaluate(sheets, sheet, calculated, work, depth + 1) {
        Number(number) => numbers.push(number)
        Boolean(value) => numbers.push(if value { 1 } else { 0 })
        Text(_) => ()
        // ONLYOFFICE ignores reference errors but rejects direct errors and empty arguments.
        _ => return Error("#VALUE!")
      }
    }
  }
  squared_deviations_result(numbers, work)
}
