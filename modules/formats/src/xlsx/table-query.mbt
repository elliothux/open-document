///|
fn Session::table_query(
  self : Session,
  sheet : Sheet,
) -> Array[Json] raise @failure.Failure {
  let tables = self
    .table_definitions(self.sheets, self.workbook, self.parts)
    .filter(table => table.sheet == sheet.id)
  if tables.is_empty() {
    return []
  }
  let reason = self.sheet_rename_reason(structure=false, tables=true)
  tables.map(table => {
    let value : Json = {
      "id": table.id,
      "name": table.name,
      "range": table.range.name(),
      "headerRow": table.headers == 1,
      "totalRow": table.totals == 1,
      "columns": table.columns.map(column => {
        let value : Json = {
          "id": column.id,
          "name": column.name,
          "calculated": column.calculated,
        }
        value
      }),
      "style": table.style.map(value => Json(value)).unwrap_or(Json::null()),
      "readOnlyReason": if !reason.is_empty() {
        reason
      } else if sheet.locked {
        "Protected worksheet"
      } else {
        table.reason
      },
    }
    value
  })
}

///|
fn Session::protect_table_cells(
  self : Session,
  sheets : Array[Sheet],
  tables : Array[StructuredTable],
) -> Unit raise @failure.Failure {
  let previous = self.table_definitions(self.sheets, self.workbook, self.parts)
  let mut scanned = 0
  for table in tables {
    let original = previous.iter().find_first(old => old.part == table.part)
    guard original is Some(original) else { continue }
    let before = self.sheets
      .iter()
      .find_first(sheet => sheet.id == original.sheet)
      .unwrap()
    let after = sheets
      .iter()
      .find_first(sheet => sheet.id == table.sheet)
      .unwrap()
    for source in [before, after] {
      for name in source.cells.keys() {
        scanned += 1
        guard scanned <= 1048576 else {
          @failure.reject(
            "limit-exceeded", "Table edit inspection exceeds budget",
          )
        }
        let address = Address::parse(name)
        if !original.range.contains(address) {
          continue
        }
        let old = before.cells.get(name)
        let cell = after.cells.get(name)
        let formula = old.bind(cell => cell.formula)
        let next_formula = cell.bind(cell => cell.formula)
        let changed = formula != next_formula ||
          (
            formula is None &&
            old.map(cell => cell.value).unwrap_or(Blank) !=
            cell.map(cell => cell.value).unwrap_or(Blank)
          )
        if !changed {
          continue
        }
        let renamed = original.name != table.name ||
          original.columns != table.columns
        let header = original.headers == 1 && address.row == original.range.top
        guard table.reason.is_empty() &&
          (
            renamed ||
            (
              !header &&
              !(original.totals == 1 && address.row == original.range.bottom) &&
              !original.columns[address.column - original.range.left].calculated
            )
          ) else {
          @failure.reject(
            "protected-content", "Table headers, totals or calculated columns require a table command",
          )
        }
      }
    }
  }
}
