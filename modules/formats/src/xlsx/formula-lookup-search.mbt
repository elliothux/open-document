///|
priv enum LookupResult {
  Found(Int)
  Missing
  Failed(String)
}

///|
fn lookup_compare(
  a : Value,
  b : Value,
  work : FormulaWork,
) -> Int raise @failure.Failure {
  work.spend()
  match (a, b) {
    (Text(a), Text(b)) => criteria_compare(a, b, work)
    _ => comparable(a, b)
  }
}

///|
fn lookup_search(
  range : FormulaRange,
  needle : Value,
  mode : Int,
  search : Int,
  last_equal : Bool,
  strict_errors : Bool,
  sheets : Array[Sheet],
  calculated : Map[(Int, String), Value],
  work : FormulaWork,
) -> LookupResult raise @failure.Failure {
  let count = range.area().to_int()
  let mut best : Int? = None
  if search.abs() == 2 {
    let mut low = 0
    let mut high = count
    while low < high {
      let middle = low + (high - low) / 2
      let value = range.value(middle.to_int64(), sheets, calculated, work)
      if value is Error(error) {
        return Failed(error)
      }
      let compared = lookup_compare(value, needle, work)
      if compared == 0 {
        if !last_equal {
          return Found(middle)
        }
        best = Some(middle)
        low = middle + 1
        continue
      }
      if (mode == -1 && compared < 0) || (mode == 1 && compared > 0) {
        best = Some(middle)
      }
      if (search == 2 && compared < 0) || (search == -2 && compared > 0) {
        low = middle + 1
      } else {
        high = middle
      }
    }
  } else {
    let pattern = if mode == 2 &&
      needle is Text(text) &&
      (text.contains("*") || text.contains("?") || text.contains("~")) {
      Some(formula_pattern(text, work))
    } else {
      None
    }
    let indices : Array[Int]? = if count <= sheets[range.sheet].cells.length() {
      None
    } else {
      let stored = aggregate_offsets([range], sheets, work)
      work.spend(amount=stored.length() + 1)
      let indices : Array[Int] = []
      let mut next = 0
      for offset in stored {
        let index = offset.to_int()
        // All absent cells in a gap have the same value; retain its first search hit.
        if next < index {
          indices.push(if search == -1 { index - 1 } else { next })
        }
        indices.push(index)
        next = index + 1
      }
      if next < count {
        indices.push(if search == -1 { count - 1 } else { next })
      }
      Some(indices)
    }
    let steps = indices.map(indices => indices.length()).unwrap_or(count)
    for step in 0..<steps {
      let position = if search == -1 { steps - step - 1 } else { step }
      let index = indices.map(indices => indices[position]).unwrap_or(position)
      let value = range.value(index.to_int64(), sheets, calculated, work)
      if value is Error(error) {
        if strict_errors {
          return Failed(error)
        }
        continue
      }
      let compared = lookup_compare(value, needle, work)
      let equal = if pattern is Some(pattern) {
        value is Text(text) && criteria_pattern(pattern, text, work)
      } else {
        compared == 0
      }
      if equal {
        return Found(index)
      }
      if (mode == -1 && compared < 0) || (mode == 1 && compared > 0) {
        if best is Some(previous) {
          let order = lookup_compare(
            value,
            range.value(previous.to_int64(), sheets, calculated, work),
            work,
          )
          if (mode == -1 && order > 0) || (mode == 1 && order < 0) {
            best = Some(index)
          }
        } else {
          best = Some(index)
        }
      }
    }
  }
  match best {
    Some(index) => Found(index)
    None => Missing
  }
}
