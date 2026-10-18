///|
fn Session::set_table_column_formula(
  self : Session,
  sheet : String,
  id : Int,
  column : Int,
  formula : String?,
) -> Json raise @failure.Failure {
  let table = self.table_for_edit(sheet, id)
  let position = table_column_index(table, column)
  let source = self.part_xml(table.part)
  let tree = table_edit_tree(table, source)
  let node = table_column_node(tree, position)
  let current = self.sheets[self.sheet_index(sheet)]
  let updates : Map[String, CellContent] = Map([])
  let formula = formula.map(text => {
    let body = text.trim().to_owned()
    let body = body.strip_prefix("=").unwrap_or(body[:]).to_owned()
    guard !body.is_empty() && body.length() <= 8192 && @xml.valid_text(body) else {
      @failure.reject(
        "limit-exceeded", "Calculated column formula must contain 1..8192 UTF-16 units",
      )
    }
    let expression = parse_formula(body)
    let first = table.range.top + table.headers
    let last = table.range.bottom - table.totals
    guard first <= last && last - first + 1 <= 4096 else {
      @failure.reject(
        "limit-exceeded", "Calculated column authoring requires 1..4096 data cells",
      )
    }
    let work : FormulaWork = {
      remaining: 1048576,
      date1904: self.date1904,
      origin: self.focus,
      names: self.formula_names(),
    }
    for row in first..<=last {
      let address = Address::{ row, column: table.range.left + position, }.name()
      let formula = expression.source(rows=row - first, invalid_ref=true)
      work.spend(amount=formula.length() + 1)
      let cell = current.cells.get(address)
      let same = same_table_formula(cell.bind(cell => cell.formula), formula)
      if !same {
        updates[address] = {
          value: Blank,
          formula: Some(formula),
          keep_shared: false,
        }
      }
    }
    if same_table_formula(table.columns[position].formula, expression.source()) {
      table.columns[position].formula.unwrap()
    } else {
      body
    }
  })
  let changes = table_formula_change(
    tree, node, "calculatedColumnFormula", formula,
  )
  let parts = self.parts.copy()
  let edits : Array[(String, @xml.Edit)] = []
  if !changes.is_empty() {
    let (document, edit) = source.edit_source(changes)
    parts[table.part] = document
    edits.push((table.part, edit))
  }
  self.finish_table_edit(table, parts, edits, updates)
}
