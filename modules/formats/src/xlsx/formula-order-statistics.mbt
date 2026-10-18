///|
fn order_statistic_function(
  name : String,
  args : Array[Expression],
  sheets : Array[Sheet],
  sheet : Int,
  calculated : Map[(Int, String), Value],
  work : FormulaWork,
  depth : Int,
) -> Value raise @failure.Failure {
  let range = args[0].aggregate_range(sheets, sheet)
  let scalar = if range is None || args[0] is Reference(_, _, None) {
    Some(args[0].evaluate(sheets, sheet, calculated, work, depth + 1))
  } else {
    None
  }
  if scalar is Some(Error(error)) {
    return Error(error)
  }
  let rank = numeric_value(
    args[1].evaluate(sheets, sheet, calculated, work, depth + 1),
  )
  if rank is Error(_) {
    return rank
  }
  guard rank is Number(rank) else { abort("Expected numeric rank") }
  if scalar is Some(value) {
    // ONLYOFFICE SMALL accepts scalar data; LARGE requires an explicit area.
    if name == "LARGE" {
      return Error("#NUM!")
    }
    let value = numeric_value(value)
    if value is Error(_) {
      return value
    }
    return if rank == 1 { value } else { Error("#NUM!") }
  }
  let range = range.unwrap()
  if name == "LARGE" && rank <= 0 {
    return Error("#N/A")
  }
  let numbers : Array[Double] = []
  for offset in aggregate_offsets([range], sheets, work) {
    let value = range.value(offset, sheets, calculated, work)
    work.spend()
    match value {
      Number(number) => numbers.push(number)
      Boolean(value) if name == "LARGE" =>
        numbers.push(if value { 1 } else { 0 })
      Error(_) => return value
      _ => ()
    }
  }
  if rank <= 0 {
    return Error("#NUM!")
  }
  let rank = if name == "LARGE" { rank.ceil() } else { rank }
  if rank > numbers.length().to_double() || rank != rank.floor() {
    return Error("#NUM!")
  }
  for size = numbers.length(); size > 1; size = (size + 1) / 2 {
    work.spend(amount=numbers.length())
  }
  numbers.sort()
  let index = rank.to_int() - 1
  Number(
    numbers[if name == "LARGE" { numbers.length() - 1 - index } else { index }],
  )
}
