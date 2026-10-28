///|
fn paired_squares_function(
  name : String,
  args : Array[Expression],
  sheets : Array[Sheet],
  sheet : Int32,
  values : Map[(Int32, String), Value],
  work : FormulaWork,
  depth : Int32,
) -> Value raise @failure.Failure {
  let qualified = args.map(arg => arg is Reference(Some(_), _, Some(_)))
  // Native qualified areas are 3D matrices; mixed 2D/3D operands do not pair.
  if qualified[0] && !qualified[1] {
    return Error("#VALUE!")
  }
  let operands : Array[(FormulaRange?, Value)] = []
  for arg in args {
    if arg is Reference(_, _, Some(_)) {
      operands.push((arg.aggregate_range(sheets, sheet), Blank))
    } else {
      let value = arg.evaluate(sheets, sheet, values, work, depth + 1)
      match value {
        Number(_) => operands.push((None, value))
        Error(_) => return value
        _ => return Error("#VALUE!")
      }
    }
  }
  if qualified[0] != qualified[1] {
    return Error("#VALUE!")
  }
  let dimensions = operands.map(operand => {
    operand.0
    .map(range => {
      (
        range.bounds.bottom - range.bounds.top + 1,
        range.bounds.right - range.bounds.left + 1,
      )
    })
    .unwrap_or((1, 1))
  })
  guard dimensions[0] == dimensions[1] else { return Error("#VALUE!") }
  let ranges = operands.iter().filter_map(operand => operand.0).collect()
  let offsets = if ranges.is_empty() {
    [0L]
  } else {
    aggregate_offsets(ranges, sheets, work)
  }
  let area = dimensions[0].0.to_int64() * dimensions[0].1.to_int64()
  guard offsets.length().to_int64() == area else { return Error("#VALUE!") }
  let mut total = 0.0
  for offset in offsets {
    work.spend()
    let pair = operands.map(operand => {
      if operand.0 is Some(range) {
        range.value(offset, sheets, values, work)
      } else {
        operand.1
      }
    })
    guard pair is [Number(x), Number(y)] else { return Error("#VALUE!") }
    total += match name {
      "SUMX2MY2" => x * x - y * y
      "SUMX2PY2" => x * x + y * y
      _ => (x - y) * (x - y)
    }
  }
  finite_result(total)
}
