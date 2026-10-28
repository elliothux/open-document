///|
fn counting_function(
  name : String,
  args : Array[Expression],
  sheets : Array[Sheet],
  sheet : Int32,
  calculated : Map[(Int32, String), Value],
  work : FormulaWork,
  depth : Int32,
) -> Value raise @failure.Failure {
  let mut count = 0.0
  if name == "COUNTBLANK" {
    guard args[0].aggregate_range(sheets, sheet) is Some(range) else {
      return Error("#REF!")
    }
    count = range.area().to_double()
  }
  for arg in args {
    for value in arg.text_items(sheets, sheet, calculated, work, depth, false) {
      work.spend()
      if name == "COUNTBLANK" {
        if value != Blank && value != Text("") {
          count -= 1
        }
      } else if value != Blank {
        count += 1
      }
    }
  }
  Number(count)
}

///|
fn conditional_function(
  name : String,
  args : Array[Expression],
  sheets : Array[Sheet],
  sheet : Int32,
  calculated : Map[(Int32, String), Value],
  work : FormulaWork,
  depth : Int32,
) -> Value raise @failure.Failure {
  let counting = name == "COUNTIF" || name == "COUNTIFS"
  let extremum = name == "MINIFS" || name == "MAXIFS"
  let multiple = extremum || ["COUNTIFS", "SUMIFS", "AVERAGEIFS"].contains(name)
  let ranges : Array[FormulaRange] = []
  let criteria : Array[(Criterion, Bool)] = []
  let first = if multiple && !counting { 1 } else { 0 }
  let end = if multiple { args.length() } else { 2 }
  for index = first; index < end; index = index + 2 {
    guard args[index].aggregate_range(sheets, sheet) is Some(range) else {
      return Error("#VALUE!")
    }
    let arg = args[index + 1]
    if arg is Reference(_, first, Some(last)) && first.address != last.address {
      return Error("#VALUE!")
    }
    ranges.push(range)
    let value = arg.evaluate(sheets, sheet, calculated, work, depth + 1)
    if extremum && value is Error(_) {
      return Error("#VALUE!")
    }
    // ONLYOFFICE MINIFS/MAXIFS stringify criteria and let an empty criterion match zero.
    criteria.push(
      (
        Criterion::new(
          if extremum {
            Text(value.display())
          } else {
            value
          },
          work,
        ),
        extremum && (value == Blank || value == Text("")),
      ),
    )
  }
  let base = ranges[0]
  let target = if counting {
    base
  } else {
    let arg = if multiple { args[0] } else { args.get(2).unwrap_or(args[0]) }
    guard arg.aggregate_range(sheets, sheet) is Some(target) else {
      return Error("#VALUE!")
    }
    if multiple {
      target
    } else {
      guard target.fit(base.bounds) is Some(target) else {
        return Error("#REF!")
      }
      target
    }
  }
  if ranges.any(range => {
      range.bounds.bottom - range.bounds.top !=
      target.bounds.bottom - target.bounds.top ||
      range.bounds.right - range.bounds.left !=
      target.bounds.right - target.bounds.left
    }) {
    return Error("#VALUE!")
  }
  let implicit = counting && criteria.all(entry => entry.0.matches(Blank, work))
  let mut count = if implicit { target.area().to_double() } else { 0.0 }
  let mut sum = 0.0
  let mut extreme : Double? = None
  let offsets = aggregate_offsets(
    if counting {
      ranges
    } else {
      [target]
    },
    sheets,
    work,
  )
  for offset in offsets {
    let mut matched = true
    for index, range in ranges {
      let actual = range.value(offset, sheets, calculated, work)
      let (criterion, empty_zero) = criteria[index]
      if !(empty_zero && actual == Number(0)) &&
        !criterion.matches(actual, work) {
        matched = false
        break
      }
    }
    if counting {
      if matched != implicit {
        count += if matched { 1 } else { -1 }
      }
    } else if matched {
      match target.value(offset, sheets, calculated, work) {
        Number(value) =>
          if extremum {
            extreme = Some(
              extreme
              .map(previous => {
                if name == "MINIFS" {
                  previous.min(value)
                } else {
                  previous.max(value)
                }
              })
              .unwrap_or(value),
            )
          } else {
            sum += value
            count += 1
          }
        Error(_) if extremum => ()
        Error(error) => return Error(error)
        _ => ()
      }
    }
  }
  if counting {
    Number(count)
  } else if extremum {
    Number(extreme.unwrap_or(0))
  } else if name == "AVERAGEIF" || name == "AVERAGEIFS" {
    if count == 0 {
      Error("#DIV/0!")
    } else {
      finite_result(sum / count)
    }
  } else {
    finite_result(sum)
  }
}
