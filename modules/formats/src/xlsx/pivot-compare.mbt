///|
fn pivot_difference(value : Value, base : Value) -> Value {
  if value is Error(_) {
    return value
  }
  if base is Error(_) {
    return base
  }
  finite_result(
    (if value is Number(number) { number } else { 0.0 }) -
    (if base is Number(number) { number } else { 0.0 }),
  )
}

///|
fn pivot_comparison(mode : String, value : Value, base : Value) -> Value {
  if mode == "difference" {
    return pivot_difference(value, base)
  }
  if base == Error("#N/A") {
    return base
  }
  if value == Blank {
    return Error("#NULL!")
  }
  if value is Error(_) && (base == Blank || base is Error(_)) {
    return value
  }
  if base == Blank || base is Error(_) {
    return Blank
  }
  pivot_ratio(
    if mode == "percentDiff" {
      pivot_difference(value, base)
    } else {
      value
    },
    base,
  )
}

///|
fn pivot_compare_series(
  field : PivotValue,
  raw : Array[Value],
  members : Array[Int],
  fixed : Int?,
) -> Array[Value] {
  let fixed = fixed.bind(item => members.search_by(value => value == item))
  raw.mapi((at, value) => {
    let target = match field.baseItem.unwrap() {
      Previous => if at == 0 { None } else { Some(at - 1) }
      Next => if at + 1 == raw.length() { None } else { Some(at + 1) }
      Member(_) => fixed
    }
    if target == Some(at) ||
      (target is None && field.baseItem is Some(Previous | Next)) {
      return if field.showDataAs == "percent" && value is Number(_) {
        pivot_ratio(value, value)
      } else {
        Blank
      }
    }
    let base = target.map(index => raw[index]).unwrap_or(Error("#N/A"))
    pivot_comparison(field.showDataAs, value, base)
  })
}
