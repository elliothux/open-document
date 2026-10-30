///|
fn Sheet::expand_shared(
  self : Sheet,
  tree : Tree,
) -> Unit raise @failure.Failure {
  let groups : Map[Int32, (Address, Range, String)] = Map([])
  for cell in self.cells.values() {
    if cell.group is Some(group) &&
      cell.formula is Some(source) &&
      !source.is_empty() {
      let formula = tree.one(cell.node, "f").unwrap()
      let range = Range::parse(formula.attribute("ref").unwrap_or(""))
      guard !groups.contains(group) &&
        range.contains(cell.address) &&
        (range.bottom - range.top + 1).to_int64() *
        (range.right - range.left + 1).to_int64() <=
        4096 else {
        @failure.reject(
          "malformed-xlsx",
          "Invalid or excessive shared formula group",
          part=self.id,
        )
      }
      groups[group] = (cell.address, range, source)
    }
  }
  let names = self.cells.keys().collect()
  for name in names {
    let cell = self.cells[name]
    if cell.group is Some(group) {
      guard groups.get(group) is Some((anchor, range, source)) &&
        range.contains(cell.address) else {
        @failure.reject(
          "malformed-xlsx",
          "Shared formula is missing its anchor or leaves its range",
          part=self.id,
        )
      }
      let shifted = shared_formula_source(
        source,
        cell.address.row - anchor.row,
        cell.address.column - anchor.column,
      ) catch {
        @failure.Failure(code~, ..) if code != "limit-exceeded" => {
          self.cells[name] = { ..cell, read_only: "Unsupported formula group", }
          continue
        }
        error => raise error
      }
      self.cells[name] = { ..cell, formula: Some(shifted), }
    }
  }
}

///|
fn shared_formula_source(
  source : String,
  rows : Int32,
  columns : Int32,
) -> String raise @failure.Failure {
  ignore(parse_formula(source))
  let spans : Array[(Int32, Int32)] = []
  let tokens = formula_tokens(source, spans~)
  let output = StringBuilder()
  let mut cursor = 0
  for index in 0..<(tokens.length() - 1) {
    if !(tokens[index] is (Word(_) | Numeric(_, _))) ||
      tokens.get(index + 1) is Some(Operator("!" | "(")) {
      continue
    }
    let (start, end) = spans[index]
    let range = tokens.get(index + 1) is Some(Operator(":")) ||
      (index > 0 && tokens[index - 1] is Operator(":"))
    let replacement = match axis_reference(source[start:end].to_owned()) {
      Some(Cell(address)) => address.shift(rows, columns).source()
      Some(Row(row, fixed)) if range => {
        let next = row + (if fixed { 0 } else { rows })
        guard next >= 1 && next <= 1048576 else {
          @failure.reject(
            "invalid-address", "Shared row reference leaves worksheet",
          )
        }
        (if fixed { "$" } else { "" }) + next.to_string()
      }
      Some(Column(column, fixed)) if range => {
        let next = column + (if fixed { 0 } else { columns })
        guard next >= 1 && next <= 16384 else {
          @failure.reject(
            "invalid-address", "Shared column reference leaves worksheet",
          )
        }
        (if fixed { "$" } else { "" }) + print_column(next)
      }
      _ => continue
    }
    output.write_view(source[cursor:start])
    output.write_string(replacement)
    cursor = end
  }
  output.write_view(source[cursor:])
  let result = output.to_string()
  guard result.length() <= 8192 else {
    @failure.reject(
      "limit-exceeded", "Expanded shared formula exceeds source budget",
    )
  }
  result
}
