///|
priv struct AxisChange {
  rows : Bool
  first : Int
  count : Int
  insert : Bool
}

///|
fn AxisChange::limit(self : AxisChange) -> Int {
  if self.rows {
    1048576
  } else {
    16384
  }
}

///|
fn AxisChange::interval(
  self : AxisChange,
  first : Int,
  last : Int,
) -> (Int, Int)? {
  if last < self.first {
    return Some((first, last))
  }
  if self.insert {
    let start = first + (if first >= self.first { self.count } else { 0 })
    if start > self.limit() {
      return None
    }
    Some((start, (last + self.count).min(self.limit())))
  } else {
    let end = self.first + self.count - 1
    let start = if first < self.first {
      first
    } else {
      first.max(end + 1) - self.count
    }
    let last = if last > end {
      last - self.count
    } else {
      last.min(self.first - 1)
    }
    if start <= last {
      Some((start, last))
    } else {
      None
    }
  }
}

///|
fn AxisChange::address(self : AxisChange, address : Address) -> Address? {
  let value = if self.rows { address.row } else { address.column }
  self
  .interval(value, value)
  .map(pair => {
    if self.rows {
      { ..address, row: pair.0, }
    } else {
      { ..address, column: pair.0, }
    }
  })
}

///|
fn AxisChange::range(self : AxisChange, range : Range) -> Range? {
  let (first, last) = if self.rows {
    (range.top, range.bottom)
  } else {
    (range.left, range.right)
  }
  self
  .interval(first, last)
  .map(pair => {
    if self.rows {
      { ..range, top: pair.0, bottom: pair.1, }
    } else {
      { ..range, left: pair.0, right: pair.1, }
    }
  })
}

///|
priv enum AxisReference {
  Cell(FormulaAddress)
  Row(Int, Bool)
  Column(Int, Bool)
}

///|
fn axis_reference(text : String) -> AxisReference? {
  try {
    return Some(Cell(formula_address(text)))
  } catch {
    _ => ()
  }
  let raw = text.strip_prefix("$").unwrap_or(text[:]).to_owned()
  if !raw.is_empty() && raw.iter().all(c => c >= '0' && c <= '9') {
    try {
      return Some(Row(Address::parse("A" + raw).row, text.has_prefix("$")))
    } catch {
      _ => ()
    }
  }
  if !raw.is_empty() && raw.iter().all(c => c.is_ascii_alphabetic()) {
    try {
      return Some(
        Column(
          Address::parse(raw.to_upper() + "1").column,
          text.has_prefix("$"),
        ),
      )
    } catch {
      _ => ()
    }
  }
  None
}

///|
fn AxisReference::value(self : AxisReference, rows : Bool) -> Int? {
  match self {
    Cell(cell) =>
      Some(if rows { cell.address.row } else { cell.address.column })
    Row(value, _) if rows => Some(value)
    Column(value, _) if !rows => Some(value)
    _ => None
  }
}

///|
fn AxisReference::source(
  self : AxisReference,
  value : Int,
  rows : Bool,
) -> String raise @failure.Failure {
  match self {
    Cell(cell) =>
      {
        ..cell,
        address: if rows {
          { ..cell.address, row: value, }
        } else {
          { ..cell.address, column: value, }
        },
      }.source()
    Row(_, fixed) => (if fixed { "$" } else { "" }) + value.to_string()
    Column(_, fixed) => (if fixed { "$" } else { "" }) + print_column(value)
  }
}

///|
fn axis_formula(
  text : String,
  current : String?,
  target : String,
  change : AxisChange,
) -> String raise @failure.Failure {
  let spans : Array[(Int, Int)] = []
  let tokens = formula_tokens(text, spans~)
  let output = StringBuilder()
  let mut cursor = 0
  let mut index = 0
  while index < tokens.length() - 1 {
    let prefix = index
    let mut sheet = current
    if tokens.get(index + 1) is Some(Operator("!")) {
      sheet = match tokens[index] {
        Word(name) | Quoted(name, true) => Some(name)
        _ => @failure.reject("protected-content", "Unknown worksheet reference")
      }
      index += 2
    }
    if tokens.get(index + 1) is Some(Operator(":")) &&
      tokens.get(index + 3) is Some(Operator("!")) {
      @failure.reject(
        "protected-content", "Three-dimensional references require structural support",
      )
    }
    let first_index = index
    let first = axis_reference(text[spans[index].0:spans[index].1].to_owned())
    let mut last_index = index
    if tokens.get(index + 1) is Some(Operator(":")) {
      last_index += 2
      guard last_index < tokens.length() - 1 &&
        !(tokens.get(last_index + 1) is Some(Operator("!"))) else {
        @failure.reject("protected-content", "Unknown range endpoint")
      }
    }
    index = last_index + 1
    guard first is Some(first) else { continue }
    if first_index == last_index && !(first is Cell(_)) {
      continue
    }
    if tokens.get(last_index + 1) is Some(Operator("(")) {
      continue
    }
    let last = if first_index == last_index {
      Some(first)
    } else {
      axis_reference(text[spans[last_index].0:spans[last_index].1].to_owned())
    }
    guard last is Some(last) else {
      @failure.reject("protected-content", "Unknown range reference")
    }
    guard (match (first, last) {
      (Cell(_), Cell(_))
      | (Row(_, _), Row(_, _))
      | (Column(_, _), Column(_, _)) => true
      _ => false
    }) else {
      @failure.reject("protected-content", "Mixed range reference kinds")
    }
    if sheet is Some(name) && name.to_lower() != target.to_lower() {
      continue
    }
    guard first.value(change.rows) is Some(a) &&
      last.value(change.rows) is Some(b) else {
      continue
    }
    let result = change.interval(a.min(b), a.max(b))
    if result == Some((a.min(b), a.max(b))) {
      continue
    }
    guard sheet is Some(_) else {
      @failure.reject(
        "protected-content", "Unscoped relative names require structural support",
      )
    }
    let (start, replacement) = if result is Some((low, high)) {
      let (a, b) = if a <= b { (low, high) } else { (high, low) }
      (
        spans[first_index].0,
        first.source(a, change.rows) +
        (if first_index == last_index {
          ""
        } else {
          ":" + last.source(b, change.rows)
        }),
      )
    } else {
      (spans[prefix].0, "#REF!")
    }
    output.write_view(text[cursor:start])
    output.write_string(replacement)
    cursor = spans[last_index].1
  }
  output.write_view(text[cursor:])
  let result = output.to_string()
  guard result.length() <= 8192 else {
    @failure.reject(
      "limit-exceeded", "Structural formula exceeds source budget",
    )
  }
  result
}
