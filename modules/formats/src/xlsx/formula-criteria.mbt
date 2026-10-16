///|
priv struct Criterion {
  operator : String
  value : Value
  pattern : Array[FormulaPattern]?
}

///|
fn Criterion::new(
  value : Value,
  work : FormulaWork,
) -> Criterion raise @failure.Failure {
  let value = match value {
    Blank => Number(0)
    Error(text) => Text(text)
    value => value
  }
  let mut operator = "="
  let value = if value is Text(text) {
    work.spend(amount=text.length())
    let mut offset = 0
    for prefix in ["<>", "<=", ">=", "=", "<", ">"] {
      if text.has_prefix(prefix) {
        operator = prefix
        offset = prefix.length()
        break
      }
    }
    let text = text[offset:].to_owned()
    match numeric_value(Text(text)) {
      Number(number) => Number(number)
      _ => Text(text)
    }
  } else {
    value
  }
  let pattern = if value is Text(text) &&
    ["=", "<>"].contains(operator) &&
    (text.contains("*") || text.contains("?") || text.contains("~")) {
    Some(formula_pattern(text, work))
  } else {
    None
  }
  { operator, value, pattern, }
}

///|
// shortcut: Criteria use simple case folding; add collation with workbook locale support.
fn criteria_compare(
  a : String,
  b : String,
  work : FormulaWork,
) -> Int raise @failure.Failure {
  work.spend(amount=a.length() + b.length())
  for index in 0..<a.length().min(b.length()) {
    let compared = search_fold(a[index].to_int()).compare(
      search_fold(b[index].to_int()),
    )
    if compared != 0 {
      return compared
    }
  }
  a.length().compare(b.length())
}

///|
fn criteria_pattern(
  pattern : Array[FormulaPattern],
  text : String,
  work : FormulaWork,
) -> Bool raise @failure.Failure {
  work.spend(amount=(pattern.length() + 1) * 2)
  let mut previous = Array::make(pattern.length() + 1, false)
  let mut next = Array::make(pattern.length() + 1, false)
  previous[0] = true
  for index, token in pattern {
    if token is Many {
      previous[index + 1] = previous[index]
    }
  }
  for offset in 0..<text.length() {
    work.spend()
    let unit = text[offset]
    next[0] = false
    for index, token in pattern {
      work.spend()
      next[index + 1] = match token {
        Many => next[index] || previous[index + 1]
        One => previous[index]
        Unit(expected) =>
          previous[index] && expected == search_fold(unit.to_int())
      }
    }
    let swap = previous
    previous = next
    next = swap
  }
  previous[pattern.length()]
}

///|
fn Criterion::matches(
  self : Criterion,
  value : Value,
  work : FormulaWork,
) -> Bool raise @failure.Failure {
  work.spend()
  let comparison = match (value, self.value) {
    (Number(a), Number(b)) => Some(a.compare(b))
    (Boolean(a), Boolean(b)) => Some(a.compare(b))
    (Text(text), Number(b)) if self.operator == "=" || self.operator == "<>" => {
      work.spend(amount=text.length())
      match numeric_value(Text(text)) {
        Number(a) => Some(a.compare(b))
        _ => None
      }
    }
    (Text(a), Text(b)) =>
      if self.pattern is Some(pattern) {
        Some(if criteria_pattern(pattern, a, work) { 0 } else { 1 })
      } else {
        Some(criteria_compare(a, b, work))
      }
    (Blank, Text("")) => Some(0)
    (Error(a), Text(b)) if self.operator == "=" || self.operator == "<>" =>
      if self.pattern is Some(_) {
        None
      } else {
        Some(criteria_compare(a, b, work))
      }
    (Boolean(a), Text(b)) if self.operator == "=" || self.operator == "<>" =>
      if self.pattern is Some(_) {
        None
      } else {
        Some(criteria_compare(if a { "TRUE" } else { "FALSE" }, b, work))
      }
    _ => None
  }
  match self.operator {
    "=" => comparison == Some(0)
    "<>" => comparison != Some(0)
    ">" => comparison is Some(value) && value > 0
    ">=" => comparison is Some(value) && value >= 0
    "<" => comparison is Some(value) && value < 0
    _ => comparison is Some(value) && value <= 0
  }
}
