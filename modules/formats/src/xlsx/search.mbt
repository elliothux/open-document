///|
pub(all) struct FindOptions {
  matchCase : Bool
  wholeCell : Bool
  formulas : Bool
  workbook : Bool
}

///|
pub fn FindOptions::new(
  matchCase~ : Bool = false,
  wholeCell~ : Bool = false,
  formulas~ : Bool = true,
  workbook~ : Bool = false,
) -> FindOptions {
  { matchCase, wholeCell, formulas, workbook, }
}

///|
priv struct SearchPattern {
  chars : Array[Char]
  prefix : Array[Int]
  options : FindOptions
}

///|
fn SearchPattern::new(
  text : String,
  options : FindOptions,
) -> SearchPattern raise @failure.Failure {
  guard !text.is_empty() && text.length() <= 32767 && @xml.valid_text(text) else {
    @failure.reject(
      "invalid-operation", "Search requires bounded nonempty literal text",
    )
  }
  let chars = text
    .iter()
    .map(ch => if options.matchCase { ch } else { @ucd.to_simple_uppercase(ch) })
    .to_array()
  let prefix = Array::make(chars.length(), 0)
  for index in 1..<chars.length() {
    let mut matched = prefix[index - 1]
    while matched > 0 && chars[index] != chars[matched] {
      matched = prefix[matched - 1]
    }
    if chars[index] == chars[matched] {
      matched += 1
    }
    prefix[index] = matched
  }
  { chars, prefix, options, }
}

///|
fn SearchPattern::matches(
  self : SearchPattern,
  text : String,
  first_only : Bool,
) -> Array[(Int, Int)] {
  let chars : Array[(Int, Char)] = []
  let mut position = 0
  for ch in text {
    chars.push((position, ch))
    position += if ch.to_int() > 0xffff { 2 } else { 1 }
  }
  let matches : Array[(Int, Int)] = []
  let mut matched = 0
  for index, (offset, ch) in chars {
    let value = if self.options.matchCase {
      ch
    } else {
      @ucd.to_simple_uppercase(ch)
    }
    while matched > 0 && value != self.chars[matched] {
      matched = self.prefix[matched - 1]
    }
    if value == self.chars[matched] {
      matched += 1
    }
    if matched != self.chars.length() {
      continue
    }
    let start = chars[index + 1 - matched].0
    let end = offset + (if ch.to_int() > 0xffff { 2 } else { 1 })
    if !self.options.wholeCell || (start == 0 && end == text.length()) {
      matches.push((start, end))
      if first_only {
        return matches
      }
      matched = 0
    } else {
      matched = self.prefix[matched - 1]
    }
  }
  matches
}

///|
priv struct CellMatch {
  sheet : Int
  cell : Cell
  text : String
  reason : String
}

///|
fn Session::find_cells(
  self : Session,
  sheet : String,
  pattern : SearchPattern,
) -> (Array[CellMatch], Bool) raise @failure.Failure {
  let target = self.sheet_index(sheet)
  let matches : Array[CellMatch] = []
  let mut scanned = 0
  for index, current in self.sheets {
    if !pattern.options.workbook && index != target {
      continue
    }
    let cells = current.cells.values().to_array()
    cells.sort_by((a, b) => {
      let row = a.address.row.compare(b.address.row)
      if row == 0 {
        a.address.column.compare(b.address.column)
      } else {
        row
      }
    })
    for cell in cells {
      if pattern.options.formulas &&
        current.locked &&
        self.styles[current.style_at(cell.address)].formula_hidden {
        continue
      }
      let text = if pattern.options.formulas && cell.formula is Some(source) {
        "=" + source
      } else {
        self.calculation
        .bind(calculation => {
          calculation.values.get((index, cell.address.name()))
        })
        .unwrap_or(cell.value)
        .display()
      }
      scanned += text.length()
      guard scanned <= 8388608 else {
        @failure.reject("limit-exceeded", "Search text budget exceeded")
      }
      if pattern.matches(text, true).is_empty() {
        continue
      }
      if matches.length() == 4096 {
        return (matches, true)
      }
      let merged = current.cell_range(cell.address)
      let edit_reason = self.cell_edit_reason(current, cell.address)
      let reason = if !edit_reason.is_empty() {
        edit_reason
      } else if cell.address.row != merged.top ||
        cell.address.column != merged.left {
        "Merged-cell contents are protected"
      } else if !pattern.options.formulas && cell.formula is Some(_) {
        "Search formulas to replace a formula result"
      } else {
        ""
      }
      matches.push({ sheet: index, cell, text, reason, })
    }
  }
  (matches, false)
}

///|
/// Finds matching cells in worksheet/row/column order without changing selection.
pub fn Session::find(
  self : Session,
  revision : Int,
  sheet : String,
  text : String,
  options : FindOptions,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let (matches, truncated) = self.find_cells(
    sheet,
    SearchPattern::new(text, options),
  )
  {
    "revision": revision,
    "truncated": truncated,
    "matches": matches.map(item => {
      "sheet": Json(self.sheets[item.sheet].id),
      "name": Json(self.sheets[item.sheet].name),
      "address": Json(item.cell.address.name()),
      "hidden": Json(self.sheets[item.sheet].state != "visible"),
      "snippet": Json(String::from_array(item.text.iter().take(80).to_array())),
      "reason": Json(item.reason),
    }),
  }
}
