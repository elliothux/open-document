///|
priv struct TableSelector {
  sections : Array[String]
  columns : Array[(String, Int, Int)]
}

///|
// Apostrophes escape structural characters inside a column heading.
fn structured_end(text : String, start : Int) -> Int raise @failure.Failure {
  let mut depth = 0
  let mut index = start
  while index < text.length() {
    match text[index].to_int() {
      39 => {
        guard index + 1 < text.length() &&
          "[]#'@".contains(text[index + 1:index + 2].to_owned()) else {
          @failure.reject(
            "formula-syntax", "Invalid structured reference escape",
          )
        }
        index += 2
        continue
      }
      91 => {
        depth += 1
        guard depth <= 3 else {
          @failure.reject(
            "formula-syntax", "Structured reference nesting exceeds syntax",
          )
        }
      }
      93 => {
        depth -= 1
        if depth == 0 {
          return index + 1
        }
      }
      _ => ()
    }
    index += 1
  }
  @failure.reject("formula-syntax", "Unterminated structured reference")
}

///|
fn structured_heading(text : String) -> String {
  let out = StringBuilder()
  let mut index = 0
  while index < text.length() {
    if text[index] == 39 {
      index += 1
    }
    let character = text.get_char(index).unwrap()
    out.write_char(character)
    index += if character.to_int() > 0xffff { 2 } else { 1 }
  }
  out.to_string()
}

///|
fn structured_escape(text : String) -> String {
  let out = StringBuilder()
  for character in text.iter() {
    if "[]#'@".contains(String::from_array([character])) {
      out.write_char('\'')
    }
    out.write_char(character)
  }
  out.to_string()
}

///|
fn table_selector(text : String) -> TableSelector raise @failure.Failure {
  guard text.has_prefix("[") && structured_end(text, 0) == text.length() else {
    @failure.reject("formula-syntax", "Invalid structured reference")
  }
  let sections : Array[String] = []
  let columns : Array[(String, Int, Int)] = []
  let mut start = 1
  let end = text.length() - 1
  if start < end && text[start] == 64 {
    sections.push("#THIS ROW")
    start += 1
  }
  let add = fn(first, last) raise @failure.Failure {
    let source = text[first:last].to_owned()
    guard !source.is_empty() else {
      @failure.reject("formula-syntax", "Empty structured reference item")
    }
    if source.has_prefix("#") {
      let section = source.to_upper()
      guard ["#ALL", "#DATA", "#HEADERS", "#TOTALS", "#THIS ROW"].contains(
          section,
        ) &&
        !sections.contains(section) else {
        @failure.reject(
          "unsupported-formula", "Unknown or duplicate table row selector",
        )
      }
      sections.push(section)
    } else {
      guard columns.length() < 2 else {
        @failure.reject(
          "unsupported-formula", "Noncontiguous table columns require union support",
        )
      }
      columns.push((structured_heading(source), first, last))
    }
  }
  if start == end {
    guard !sections.is_empty() else {
      @failure.reject("formula-syntax", "Empty structured reference")
    }
  } else if text[start] != 91 {
    add(start, end)
  } else {
    let mut separator = 0
    while start < end {
      guard text[start] == 91 else {
        @failure.reject("formula-syntax", "Expected structured item bracket")
      }
      let last = structured_end(text, start)
      guard last <= end else {
        @failure.reject("formula-syntax", "Invalid structured item")
      }
      let before = columns.length()
      add(start + 1, last - 1)
      if before > 0 {
        guard separator == 58 && columns.length() == before + 1 else {
          @failure.reject(
            "unsupported-formula", "Noncontiguous structured columns require union support",
          )
        }
      } else if separator == 58 {
        @failure.reject(
          "formula-syntax", "Table column range requires two columns",
        )
      }
      start = last
      if start < end {
        separator = text[start].to_int()
        guard separator == 44 || separator == 58 else {
          @failure.reject("formula-syntax", "Invalid structured item separator")
        }
        start += 1
        guard start < end else {
          @failure.reject("formula-syntax", "Missing structured item")
        }
      }
    }
    if columns.length() == 2 && separator != 58 {
      @failure.reject(
        "unsupported-formula", "Noncontiguous structured columns require union support",
      )
    }
  }
  guard !sections.contains("#THIS ROW") || sections.length() == 1 else {
    @failure.reject(
      "formula-syntax", "This row cannot combine with table sections",
    )
  }
  { sections, columns, }
}

///|
fn structured_reference(
  name : String?,
  selector : String,
  sheets : Array[Sheet],
  sheet : Int,
  origin : Address,
  work : FormulaWork,
) -> Expression raise @failure.Failure {
  work.spend(amount=selector.length() + work.names.tables.length())
  let table = work.names.tables
    .iter()
    .find_first(table => {
      if name is Some(name) {
        table.name.to_upper() == name.to_upper()
      } else {
        sheet >= 0 &&
        table.sheet == sheets[sheet].id &&
        table.range.contains(origin)
      }
    })
  guard table is Some(table) else { return Constant(Error("#NAME?")) }
  guard table.reason.is_empty() else {
    @failure.reject("unsupported-formula", table.reason)
  }
  let query = table_selector(selector)
  let mut left = table.range.left
  let mut right = table.range.right
  if !query.columns.is_empty() {
    let indices = query.columns.map(item => {
      table.columns.search_by(column => {
        column.name.to_upper() == item.0.to_upper()
      })
    })
    guard indices[0] is Some(first) else { return Constant(Error("#REF!")) }
    let last = if indices.length() == 2 {
      guard indices[1] is Some(last) else { return Constant(Error("#REF!")) }
      last
    } else {
      first
    }
    left += first.min(last)
    right = table.range.left + first.max(last)
  }
  let data_top = table.range.top + table.headers
  let data_bottom = table.range.bottom - table.totals
  let mut top = data_top
  let mut bottom = data_bottom
  let sections = if query.sections.is_empty() {
    ["#DATA"]
  } else {
    query.sections
  }
  if sections.contains("#THIS ROW") {
    guard origin.row >= data_top && origin.row <= data_bottom else {
      return Constant(Error("#VALUE!"))
    }
    top = origin.row
    bottom = origin.row
  } else if sections.contains("#ALL") {
    top = table.range.top
    bottom = table.range.bottom
  } else {
    let rows : Array[(Int, Int)] = []
    for section in sections {
      let interval = match section {
        "#HEADERS" if table.headers == 1 => (table.range.top, table.range.top)
        "#TOTALS" if table.totals == 1 =>
          (table.range.bottom, table.range.bottom)
        "#DATA" if data_top <= data_bottom => (data_top, data_bottom)
        _ => return Constant(Error("#REF!"))
      }
      rows.push(interval)
    }
    rows.sort_by((a, b) => a.0.compare(b.0))
    top = rows[0].0
    bottom = rows[0].1
    for row in rows[1:] {
      guard row.0 <= bottom + 1 else {
        @failure.reject(
          "unsupported-formula", "Disjoint table sections require union support",
        )
      }
      bottom = bottom.max(row.1)
    }
  }
  guard top <= bottom else { return Constant(Error("#REF!")) }
  let target = sheets
    .iter()
    .find_first(sheet => sheet.id == table.sheet)
    .unwrap().name
  let first : FormulaAddress = {
    address: { row: top, column: left, },
    fixed_row: true,
    fixed_column: true,
  }
  let last : FormulaAddress = {
    address: { row: bottom, column: right, },
    fixed_row: true,
    fixed_column: true,
  }
  Reference(Some(target), first, if first == last { None } else { Some(last) })
}
