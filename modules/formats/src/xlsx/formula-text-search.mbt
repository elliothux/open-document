///|
fn formula_find(
  needle : String,
  text : String,
  start : Int,
  work : FormulaWork,
) -> Int? raise @failure.Failure {
  for index in start..<=(text.length() - needle.length()) {
    let mut found = true
    for offset in 0..<needle.length() {
      work.spend()
      if text[index + offset] != needle[offset] {
        found = false
        break
      }
    }
    if found {
      return Some(index)
    }
  }
  None
}

///|
priv enum FormulaPattern {
  Many
  One
  Unit(Int)
}

///|
fn search_fold(unit : Int) -> Int {
  guard unit.to_char() is Some(character) else { return unit }
  let upper = @ucd.to_simple_uppercase(character).to_int()
  // Match the reference's non-Unicode regular-expression case canonicalization.
  if upper > 0xffff || (unit >= 128 && upper < 128) {
    unit
  } else {
    upper
  }
}

///|
fn search_first(a : Int, b : Int) -> Int {
  if a < 0 {
    b
  } else if b < 0 {
    a
  } else {
    a.min(b)
  }
}

///|
fn formula_search(
  needle : String,
  text : String,
  start : Int,
  work : FormulaWork,
) -> Int? raise @failure.Failure {
  let pattern : Array[FormulaPattern] = []
  let mut index = 0
  while index < needle.length() {
    work.spend()
    let unit = needle[index].to_int()
    if unit == 126 &&
      index + 1 < needle.length() &&
      [42, 63, 126].contains(needle[index + 1].to_int()) {
      index += 1
      pattern.push(Unit(search_fold(needle[index].to_int())))
    } else if unit == 42 {
      if !(pattern.last() is Some(Many)) {
        pattern.push(Many)
      }
    } else if unit == 63 {
      pattern.push(One)
    } else {
      pattern.push(Unit(search_fold(unit)))
    }
    index += 1
  }
  let mut previous = Array::make(pattern.length() + 1, -1)
  let mut next = Array::make(pattern.length() + 1, -1)
  previous[0] = start
  for index, token in pattern {
    if token is Many {
      previous[index + 1] = previous[index]
    }
  }
  if previous[pattern.length()] >= 0 {
    return Some(start)
  }
  let mut result = -1
  for offset in start..<text.length() {
    work.spend()
    let unit = text[offset].to_int()
    let folded = search_fold(unit)
    let wildcard = ![10, 13, 0x2028, 0x2029].contains(unit)
    next[0] = offset + 1
    for index, token in pattern {
      work.spend()
      next[index + 1] = match token {
        Many =>
          search_first(
            next[index],
            if wildcard {
              previous[index + 1]
            } else {
              -1
            },
          )
        One => if wildcard { previous[index] } else { -1 }
        Unit(expected) => if expected == folded { previous[index] } else { -1 }
      }
    }
    result = search_first(result, next[pattern.length()])
    if result == start {
      return Some(start)
    }
    let swap = previous
    previous = next
    next = swap
  }
  if result < 0 {
    None
  } else {
    Some(result)
  }
}
