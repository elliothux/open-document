///|
/// Rechecks the query and commits selected cells or all results as one transaction.
pub fn Session::replace_matches(
  self : Session,
  revision : Int32,
  sheet : String,
  text : String,
  options : FindOptions,
  replacement : String,
  index : Int32?,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  guard self.revision < 2147483647 &&
    replacement.length() <= 32767 &&
    @xml.valid_text(replacement) else {
    @failure.reject(
      "limit-exceeded", "Replacement text or revision exceeds budget",
    )
  }
  let pattern = SearchPattern::new(text, options)
  let (matches, truncated) = self.find_cells(sheet, pattern)
  if index is Some(index) {
    guard index >= 0 && index < matches.length() else {
      @failure.reject("invalid-operation", "Search result index is invalid")
    }
  } else {
    guard !truncated else {
      @failure.reject(
        "limit-exceeded", "Find fewer cells before replacing all results",
      )
    }
  }
  let updates : Map[Int32, Map[String, CellContent]] = Map([])
  let mut selection = self.selection
  let mut units = 0
  for found, item in matches {
    if index is Some(index) && found != index {
      continue
    }
    guard item.reason.is_empty() else {
      @failure.reject("protected-content", item.reason)
    }
    let ranges = pattern.matches(item.text, false)
    let out = StringBuilder()
    let mut cursor = 0
    let mut length = 0
    for (start, end) in ranges {
      length += start - cursor + replacement.length()
      guard length <= 32767 else {
        @failure.reject(
          "limit-exceeded", "Replacement cell exceeds text budget",
        )
      }
      out.write_view(item.text[cursor:start])
      out.write_string(replacement)
      cursor = end
    }
    length += item.text.length() - cursor
    guard length <= 32767 else {
      @failure.reject("limit-exceeded", "Replacement cell exceeds text budget")
    }
    out.write_view(item.text[cursor:])
    let next = out.to_string()
    if next == item.text {
      continue
    }
    units += next.length()
    guard units <= 1048576 else {
      @failure.reject(
        "limit-exceeded", "Replacement input exceeds UTF-16 budget",
      )
    }
    let content = if options.formulas && item.cell.formula is Some(_) {
      cell_content(next, false)
    } else {
      {
        value: input_value(next, literal=item.cell.value is Text(_)),
        formula: None,
        keep_shared: false,
      }
    }
    let cells = updates.get(item.sheet).unwrap_or(Map([]))
    cells[item.cell.address.name()] = content
    updates[item.sheet] = cells
    if index is Some(_) && self.sheets[item.sheet].state == "visible" {
      let address = item.cell.address
      selection = (
        self.sheets[item.sheet].id,
        {
          top: address.row,
          bottom: address.row,
          left: address.column,
          right: address.column,
        },
      )
    }
  }
  self.commit_cells(updates, selection)
}
