///|
fn Calculation::protect_uncomputed(
  self : Calculation,
  original : Array[Sheet],
  next : Calculation,
  sheets : Array[Sheet],
  work : FormulaWork,
) -> Unit raise @failure.Failure {
  if self.uncomputed.is_empty() && next.uncomputed.is_empty() {
    return
  }
  let indices : Map[String, Int] = Map([])
  let old_indices : Map[String, Int] = Map([])
  for index, sheet in sheets {
    indices[sheet.id] = index
  }
  for index, sheet in original {
    old_indices[sheet.id] = index
  }
  for key, reason in next.uncomputed {
    work.spend()
    guard old_indices.get(sheets[key.0].id) is Some(index) &&
      self.uncomputed.contains((index, key.1)) else {
      @failure.reject("unsupported-formula", reason)
    }
  }
  for key, reason in self.uncomputed {
    work.spend()
    let message = "Edit affects uncalculated formula " +
      original[key.0].name +
      "!" +
      key.1 +
      ": " +
      reason
    guard indices.get(original[key.0].id) is Some(index) else {
      @failure.reject("protected-content", message)
    }
    let target = (index, key.1)
    guard next.uncomputed.contains(target) &&
      self.sources.get(key) == next.sources.get(target) &&
      self.expressions.get(key) == next.expressions.get(target) &&
      original[key.0].cells[key.1].value == sheets[index].cells[key.1].value else {
      @failure.reject("protected-content", message)
    }
    let before = self.dependencies[key]
    let after = next.dependencies[target]
    guard before.length() == after.length() else {
      @failure.reject("protected-content", message)
    }
    for offset, dependency in before {
      work.spend()
      let updated = after[offset]
      let old_sheet = original[dependency.sheet]
      let sheet = sheets[updated.sheet]
      guard old_sheet.id == sheet.id && dependency.range == updated.range else {
        @failure.reject("protected-content", message)
      }
      let visibility = self.expressions[key].contains_subtotal()
      if visibility &&
        subtotal_filtered(old_sheet, work) != subtotal_filtered(sheet, work) {
        @failure.reject("protected-content", message)
      }
      // Compare sparse cells in both directions, including newly occupied blanks.
      for source in [old_sheet, sheet] {
        for address, cell in source.cells {
          work.spend()
          if !dependency.range.contains(cell.address) {
            continue
          }
          let old_cell = old_sheet.cells.get(address)
          let new_cell = sheet.cells.get(address)
          let old_value = self.values
            .get((dependency.sheet, address))
            .unwrap_or(old_cell.map(cell => cell.value).unwrap_or(Blank))
          let value = next.values
            .get((updated.sheet, address))
            .unwrap_or(new_cell.map(cell => cell.value).unwrap_or(Blank))
          guard old_value == value &&
            old_cell.bind(cell => cell.formula) ==
            new_cell.bind(cell => cell.formula) &&
            (
              !visibility ||
              (old_sheet.dimensions.rows.size(cell.address.row) == 0) ==
              (sheet.dimensions.rows.size(cell.address.row) == 0)
            ) else {
            @failure.reject("protected-content", message)
          }
        }
      }
    }
  }
}

///|
fn Session::calculation_reason(
  self : Session,
  sheet : Int,
  address : Address,
) -> String raise @failure.Failure {
  self.calculation
  .bind(calculation => calculation.uncomputed.get((sheet, address.name())))
  .unwrap_or(self.read_only)
}
