///|
fn determinant_function(
  arg : Expression,
  sheets : Array[Sheet],
  sheet : Int32,
  values : Map[(Int32, String), Value],
  work : FormulaWork,
  depth : Int32,
) -> Value raise @failure.Failure {
  guard arg is Reference(_, _, Some(_)) else {
    ignore(arg.evaluate(sheets, sheet, values, work, depth + 1))
    return Error("#N/A")
  }
  let range = arg.aggregate_range(sheets, sheet).unwrap()
  let size = range.bounds.bottom - range.bounds.top + 1
  guard size == range.bounds.right - range.bounds.left + 1 else {
    return Error("#VALUE!")
  }
  let offsets = aggregate_offsets([range], sheets, work)
  guard offsets.length().to_int64() == range.area() else {
    return Error("#N/A")
  }
  work.spend(amount=offsets.length())
  let matrix = Array::make(offsets.length(), 0.0)
  for offset in offsets {
    matrix[offset.to_int()] = match range.value(offset, sheets, values, work) {
      Number(number) => number
      Blank | Text(_) => return Error("#N/A")
      Boolean(_) | Error(_) => @double.not_a_number
    }
  }
  let mut denominator = 1.0
  let mut exchanges = 0
  // Native fraction-free elimination uses the largest absolute column pivot.
  for pivot in 0..<(size - 1) {
    let mut best = pivot
    let mut largest = matrix[pivot * size + pivot].abs()
    for row in (pivot + 1)..<size {
      work.spend()
      let candidate = matrix[row * size + pivot].abs()
      if candidate > largest {
        best = row
        largest = candidate
      }
    }
    if best != pivot {
      for column in 0..<size {
        work.spend()
        let value = matrix[pivot * size + column]
        matrix[pivot * size + column] = matrix[best * size + column]
        matrix[best * size + column] = value
      }
      exchanges += 1
    } else if largest == 0 {
      return Number(0)
    }
    let first = matrix[pivot * size + pivot]
    for row in (pivot + 1)..<size {
      let second = matrix[row * size + pivot]
      matrix[row * size + pivot] = 0
      for column in (pivot + 1)..<size {
        work.spend()
        matrix[row * size + column] = (
            matrix[row * size + column] * first -
            matrix[pivot * size + column] * second
          ) /
          denominator
      }
    }
    denominator = first
  }
  let result = matrix[matrix.length() - 1] *
    (if exchanges % 2 == 0 { 1.0 } else { -1.0 })
  if result.is_nan() {
    Error("#N/A")
  } else {
    finite_result(result)
  }
}
