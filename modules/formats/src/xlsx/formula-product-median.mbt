///|
fn product_median_function(
  name : String,
  args : Array[Expression],
  sheets : Array[Sheet],
  sheet : Int,
  calculated : Map[(Int, String), Value],
  work : FormulaWork,
  depth : Int,
) -> Value raise @failure.Failure {
  let numbers : Array[Double] = []
  let mut product = 1.0
  for arg in args {
    let reference = arg.aggregate_range(sheets, sheet)
    let values = if reference is Some(range) {
      aggregate_offsets([range], sheets, work).map(offset => {
        range.value(offset, sheets, calculated, work)
      })
    } else {
      [arg.evaluate(sheets, sheet, calculated, work, depth + 1)]
    }
    for value in values {
      work.spend()
      let value = if name == "MEDIAN" {
        match value {
          Number(_) => value
          Boolean(_) if reference is None => numeric_value(value)
          Text(_) => continue
          _ if reference is Some(_) => continue
          _ => return Error("#VALUE!")
        }
      } else {
        if value is Text(text) {
          work.spend(amount=text.length())
        }
        match value {
          Blank => continue
          Boolean(_) if reference is Some(_) => continue
          Text(_) if reference is Some(_) => {
            let value = numeric_value(value)
            if value is Error(_) {
              continue
            }
            value
          }
          _ => numeric_value(value)
        }
      }
      match value {
        Error(_) => return value
        Number(number) => {
          numbers.push(number)
          if name == "PRODUCT" {
            product *= number
            if product.is_nan() || product.is_inf() {
              return Error("#NUM!")
            }
          }
        }
        _ => abort("Expected numeric aggregate value")
      }
    }
  }
  if name == "PRODUCT" {
    return Number(if numbers.is_empty() { 0 } else { product })
  }
  if numbers.is_empty() {
    return Error("#VALUE!")
  }
  for size = numbers.length(); size > 1; size = (size + 1) / 2 {
    work.spend(amount=numbers.length())
  }
  numbers.sort()
  let middle = numbers.length() / 2
  finite_result(
    if numbers.length() % 2 == 0 {
      (numbers[middle - 1] + numbers[middle]) / 2
    } else {
      numbers[middle]
    },
  )
}
