///|
fn Sheet::expand_shared(
  self : Sheet,
  tree : Tree,
) -> Unit raise @failure.Failure {
  let groups : Map[Int, (Address, Range, String)] = Map([])
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
      let shifted = parse_formula(source).source(
        rows=cell.address.row - anchor.row,
        columns=cell.address.column - anchor.column,
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
