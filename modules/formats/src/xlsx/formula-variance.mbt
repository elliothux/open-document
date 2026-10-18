///|
fn variance_result(
  numbers : Array[Double],
  sample : Bool,
  work : FormulaWork,
) -> Value raise @failure.Failure {
  let count = numbers.length()
  if count < (if sample { 2 } else { 1 }) {
    return Error("#DIV/0!")
  }
  let mut mean = 0.0
  let mut squared = 0.0
  for index, number in numbers {
    work.spend()
    let delta = number - mean
    mean += delta / (index + 1).to_double()
    squared += delta * (number - mean)
  }
  if squared.is_nan() || squared.is_inf() {
    return Error("#NUM!")
  }
  finite_result(
    squared.max(0) / (if sample { count - 1 } else { count }).to_double(),
  )
}

///|
fn statistical_function(
  name : String,
  args : Array[Expression],
  sheets : Array[Sheet],
  sheet : Int,
  calculated : Map[(Int, String), Value],
  work : FormulaWork,
  depth : Int,
) -> Value raise @failure.Failure {
  let sample_deviation = name == "STDEV" || name == "STDEV.S"
  let deviation = sample_deviation || name == "STDEVP" || name == "STDEV.P"
  let numbers : Array[Double] = []
  for arg in args {
    let reference = arg.aggregate_range(sheets, sheet)
    let items = if reference is Some(range) {
      aggregate_offsets([range], sheets, work).map(offset => {
        range.value(offset, sheets, calculated, work)
      })
    } else {
      [arg.evaluate(sheets, sheet, calculated, work, depth + 1)]
    }
    for value in items {
      work.spend()
      match value {
        Number(number) => numbers.push(number)
        Error(_) if !sample_deviation => return value
        Text(_) | Blank if reference is None && sample_deviation =>
          match numeric_value(value) {
            Number(number) => numbers.push(number)
            _ => ()
          }
        Boolean(_) if reference is None =>
          match numeric_value(value) {
            Number(number) => numbers.push(number)
            _ => abort("Boolean converts to a number")
          }
        Text(_) | Blank if reference is None && name != "VAR" =>
          // ONLYOFFICE population functions and modern VAR.S count direct text/empty as zero.
          numbers.push(0)
        _ => ()
      }
    }
  }
  // ONLYOFFICE sample deviation ignores errors and returns zero for no numeric members.
  if sample_deviation && numbers.is_empty() {
    return Number(0)
  }
  let result = variance_result(
    numbers,
    sample_deviation || name == "VAR" || name == "VAR.S",
    work,
  )
  match result {
    Number(number) if deviation => finite_result(number.sqrt())
    value => value
  }
}
