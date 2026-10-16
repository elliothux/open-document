///|
priv struct AxisChange {
  rows : Bool
  first : Int
  count : Int
  insert : Bool
  band : (Int, Int)?
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
  if self.band is Some((first, last)) {
    let value = if self.rows { address.column } else { address.row }
    if value < first || value > last {
      return Some(address)
    }
  }
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
  if self.band is Some((low, high)) {
    let (a, b) = if self.rows {
      (range.left, range.right)
    } else {
      (range.top, range.bottom)
    }
    if a < low || b > high {
      // ONLYOFFICE Range.isIntersectForShift trims a partially deleted edge, but leaves other crossing references intact.
      if !self.insert && first >= self.first && last < self.first + self.count {
        let clipped = if a >= low && a <= high {
          Some((high + 1, b))
        } else if b >= low && b <= high {
          Some((a, low - 1))
        } else {
          None
        }
        if clipped is Some((a, b)) && a <= b {
          return Some(
            if self.rows {
              { ..range, left: a, right: b, }
            } else {
              { ..range, top: a, bottom: b, }
            },
          )
        }
      }
      return Some(range)
    }
  }
  self
  .interval(first, last)
  .map(pair => {
    if self.rows {
      {
        ..range,
        top: pair.0,
        bottom: if first < last && last == self.limit() {
          self.limit()
        } else {
          pair.1
        },
      }
    } else {
      {
        ..range,
        left: pair.0,
        right: if first < last && last == self.limit() {
          self.limit()
        } else {
          pair.1
        },
      }
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
fn AxisReference::point(self : AxisReference) -> Address {
  match self {
    Cell(cell) => cell.address
    Row(row, _) => { row, column: 1, }
    Column(column, _) => { row: 1, column, }
  }
}

///|
fn AxisReference::source(
  self : AxisReference,
  address : Address,
  range : Range,
) -> String raise @failure.Failure {
  match self {
    Cell(cell) => { ..cell, address, }.source()
    Row(_, fixed) if range.left == 1 && range.right == 16384 =>
      (if fixed { "$" } else { "" }) + address.row.to_string()
    Column(_, fixed) if range.top == 1 && range.bottom == 1048576 =>
      (if fixed { "$" } else { "" }) + print_column(address.column)
    Row(_, fixed) =>
      FormulaAddress::{ address, fixed_row: fixed, fixed_column: false, }.source()
    Column(_, fixed) =>
      FormulaAddress::{ address, fixed_row: false, fixed_column: fixed, }.source()
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
    let a = first.point()
    let b = last.point()
    let range : Range = match first {
      Row(_, _) =>
        {
          top: a.row.min(b.row),
          bottom: a.row.max(b.row),
          left: 1,
          right: 16384,
        }
      Column(_, _) =>
        {
          top: 1,
          bottom: 1048576,
          left: a.column.min(b.column),
          right: a.column.max(b.column),
        }
      Cell(_) =>
        {
          top: a.row.min(b.row),
          bottom: a.row.max(b.row),
          left: a.column.min(b.column),
          right: a.column.max(b.column),
        }
    }
    let result = change.range(range)
    if result == Some(range) {
      continue
    }
    guard sheet is Some(_) else {
      @failure.reject(
        "protected-content", "Unscoped relative names require structural support",
      )
    }
    let (start, replacement) = if result is Some(next) {
      let start = {
        row: if a.row <= b.row {
          next.top
        } else {
          next.bottom
        },
        column: if a.column <= b.column {
          next.left
        } else {
          next.right
        },
      }
      let end = {
        row: if a.row <= b.row {
          next.bottom
        } else {
          next.top
        },
        column: if a.column <= b.column {
          next.right
        } else {
          next.left
        },
      }
      (
        spans[first_index].0,
        first.source(start, next) +
        (if first_index == last_index {
          ""
        } else {
          ":" + last.source(end, next)
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
