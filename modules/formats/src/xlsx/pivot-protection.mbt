///|
fn Session::maintain_pivots(
  self : Session,
  sheets : Array[Sheet],
  calculation : Calculation,
  parts : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
  edited : Array[String],
  moved : Map[String, Range],
) -> Unit raise @failure.Failure {
  let pivots = self.pivot_locations()
  if pivots.is_empty() {
    return
  }
  let mut work = 0
  for pivot in pivots {
    if edited.contains(pivot.part) {
      continue
    }
    let before = self.sheets[self.sheet_index(pivot.sheet)]
    guard sheets.iter().find_first(sheet => sheet.id == pivot.sheet)
      is Some(after) else {
      @failure.reject(
        "protected-content", "Pivot worksheet removal requires pivot resource maintenance",
      )
    }
    if !edited.contains(pivot.part) {
      let destination = moved.get(pivot.part).unwrap_or(pivot.range)
      guard destination.right - destination.left ==
        pivot.range.right - pivot.range.left &&
        destination.bottom - destination.top ==
        pivot.range.bottom - pivot.range.top else {
        @failure.reject(
          "protected-content", "Pivot result moves must preserve their complete rectangle",
        )
      }
      let rows = destination.top - pivot.range.top
      let columns = destination.left - pivot.range.left
      let keys : Map[String, Bool] = Map([])
      for
        (sheet, range, row_delta, column_delta) in [
          (before, pivot.range, 0, 0),
          (after, destination, rows, columns),
        ] {
        for _, cell in sheet.cells {
          work += 1
          guard work <= 1048576 else {
            @failure.reject(
              "limit-exceeded", "Pivot edit inspection exceeds budget",
            )
          }
          if range.contains(cell.address) {
            keys[Address::{
              row: cell.address.row - row_delta,
              column: cell.address.column - column_delta,
            }.name()] = true
          }
        }
      }
      for key in keys.keys() {
        let old = before.cells.get(key)
        let address = Address::parse(key)
        let next = after.cells.get(
          Address::{
            row: address.row + rows,
            column: address.column + columns,
          }.name(),
        )
        guard old.map(c => c.value).unwrap_or(Blank) ==
          next.map(c => c.value).unwrap_or(Blank) &&
          old.bind(c => c.formula) == next.bind(c => c.formula) else {
          @failure.reject(
            "protected-content", "Pivot result cells require a pivot command",
          )
        }
      }
    }
    let mut changed = false
    if pivot.sourceSheet is Some(source) && pivot.source is Some(range) {
      let old_index = self.sheet_index(source)
      guard sheets.search_by(sheet => sheet.id == source) is Some(next_index) else {
        @failure.reject(
          "protected-content", "Pivot source removal requires reference maintenance",
        )
      }
      let old_sheet = self.sheets[old_index]
      let next_sheet = sheets[next_index]
      let keys : Map[String, Bool] = Map([])
      for sheet in [old_sheet, next_sheet] {
        for key, cell in sheet.cells {
          work += 1
          guard work <= 1048576 else {
            @failure.reject(
              "limit-exceeded", "Pivot source inspection exceeds budget",
            )
          }
          if range.contains(cell.address) {
            keys[key] = true
          }
        }
      }
      for key in keys.keys() {
        let old = self.calculation
          .bind(calc => calc.values.get((old_index, key)))
          .unwrap_or(
            old_sheet.cells.get(key).map(cell => cell.value).unwrap_or(Blank),
          )
        let next = calculation.values
          .get((next_index, key))
          .unwrap_or(
            next_sheet.cells.get(key).map(cell => cell.value).unwrap_or(Blank),
          )
        if old != next ||
          old_sheet.style_at(Address::parse(key)) !=
          next_sheet.style_at(Address::parse(key)) {
          changed = true
          break
        }
      }
    }
    if pivot.sourceSheet is None || pivot.source is None {
      if pivot.sourceSheet is None && pivot.source is Some(_) {
        ignore(
          self.pivot_settings(
            pivot,
            shared=true,
            source_sheet=Some(pivot.sheet),
          ),
        )
        continue
      }
      for original in self.sheets {
        guard sheets.iter().find_first(sheet => sheet.id == original.id)
          is Some(candidate) else {
          @failure.reject(
            "protected-content", "Extended pivot source requires reference maintenance",
          )
        }
        for sheet in [original, candidate] {
          for key, _ in sheet.cells {
            work += 1
            guard work <= 1048576 else {
              @failure.reject(
                "limit-exceeded", "Pivot source inspection exceeds budget",
              )
            }
            let before = original.cells.get(key)
            let after = candidate.cells.get(key)
            guard before.map(cell => cell.value).unwrap_or(Blank) ==
              after.map(cell => cell.value).unwrap_or(Blank) &&
              before.bind(cell => cell.formula) ==
              after.bind(cell => cell.formula) &&
              original.style_at(Address::parse(key)) ==
              candidate.style_at(Address::parse(key)) else {
              @failure.reject(
                "protected-content", "Extended pivot source requires reference-aware cell editing",
              )
            }
          }
        }
      }
    }
    if changed {
      let original = parts
        .get(pivot.cache)
        .unwrap_or_else(() => self.part_xml(pivot.cache))
      let changes = metadata_changes(original.nodes()[0], [("invalid", "1")])
      if !changes.is_empty() {
        let (document, edit) = original.edit_source(changes)
        parts[pivot.cache] = document
        edits.push((pivot.cache, edit))
      }
    }
  }
}
