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
  let reason = self.sheet_rename_reason(
    structure=false,
    tables=true,
    pivots=true,
    analysis=true,
    pictures=true,
    charts=true,
  )
  let work : FormulaWork = {
    remaining: 1048576,
    date1904: self.date1904,
    origin: self.focus,
    names: self.formula_names(),
  }
  let (filters, filter_reason) = (self.sheet_filters(sheet, self.parts), "") catch {
    @failure.Failure(message~, ..) => (Map([]), message)
  }
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
          "formula": column.formula.map(Json::string).unwrap_or(Json::null()),
          "totalFunction": column.total_function
          .map(Json::string)
          .unwrap_or(Json::null()),
          "totalLabel": column.total_label
          .map(Json::string)
          .unwrap_or(Json::null()),
          "totalFormula": column.total_formula
          .map(Json::string)
          .unwrap_or(Json::null()),
        }
        value
      }),
      "style": table.style.map(value => Json(value)).unwrap_or(Json::null()),
      "firstColumn": table.first_column,
      "lastColumn": table.last_column,
      "rowStripes": table.row_stripes,
      "columnStripes": table.column_stripes,
      "filter": self.filter_query(
        self.sheet_index(sheet.id),
        table=Some(table),
        states=Some(filters),
        failure=filter_reason,
        work=Some(work),
      ),
      "readOnlyReason": if !reason.is_empty() {
        reason
      } else if sheet.locked {
        "Protected worksheet"
      } else if !table.style_reason.is_empty() {
        table.style_reason
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
  edited~ : Array[String] = [],
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
            edited.contains(table.part) ||
            (
              !edited.is_empty() &&
              formula is Some(_) &&
              next_formula is Some(_)
            ) ||
            (
              !header &&
              !(original.totals == 1 && address.row == original.range.bottom) &&
              original.columns[address.column - original.range.left].formula
              is None
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
