///|
fn Session::show_table_totals(
  self : Session,
  sheet : String,
  id : Int,
  visible : Bool,
) -> Json raise @failure.Failure {
  let table = self.table_for_edit(sheet, id)
  if (table.totals == 1) == visible {
    return self.query()
  }
  guard table.range.bottom - table.range.top + 1 > table.headers + table.totals &&
    (!visible || table.range.bottom < 1048576) else {
    @failure.reject(
      "limit-exceeded", "Totals row needs data and an available worksheet row",
    )
  }
  let current = self.sheets[self.sheet_index(sheet)]
  let range : Range = {
    ..table.range,
    bottom: table.range.bottom + (if visible { 1 } else { -1 }),
  }
  let target : Range = { ..range, top: range.bottom, }
  if visible {
    guard !current.merges.any(merge => merge.intersects(target)) &&
      !self
      .table_definitions(self.sheets, self.workbook, self.parts)
      .any(other => {
        other.part != table.part &&
        other.sheet == sheet &&
        other.range.intersects(target)
      }) &&
      !read_filter(current)
      .map(filter => filter.bounds.intersects(target))
      .unwrap_or(false) else {
      @failure.reject(
        "protected-content", "Totals destination overlaps a table merge or filter",
      )
    }
    for column in target.left..<=target.right {
      guard current.cells
        .get(Address::{ row: target.top, column, }.name())
        .map(cell => {
          cell.value == Blank &&
          cell.formula is None &&
          cell.read_only.is_empty() &&
          cell.group is None
        })
        .unwrap_or(true) else {
        @failure.reject(
          "protected-content", "Totals destination contains data or protected source",
        )
      }
    }
  }
  let parts = self.parts.copy()
  let edits : Array[(String, @xml.Edit)] = []
  let updates : Map[String, CellContent] = Map([])
  if visible &&
    table.columns.all(column => {
      column.total_function is None &&
      column.total_label is None &&
      column.total_formula is None
    }) {
    if table.columns.length() > 1 {
      self.write_table_total(table, 0, Label("Summary"), parts, edits)
    }
    let position = table.columns.length() - 1
    let mut numeric = true
    let index = self.sheet_index(sheet)
    for cell in current.cells.values() {
      if cell.address.column != table.range.right ||
        cell.address.row < table.range.top + table.headers ||
        cell.address.row > table.range.bottom {
        continue
      }
      let address = cell.address.name()
      let value = self.calculation
        .bind(calculation => calculation.values.get((index, address)))
        .unwrap_or(cell.value)
      if value != Blank && !(value is Number(_)) {
        numeric = false
        break
      }
    }
    self.write_table_total(
      table,
      position,
      Aggregate(if numeric { "sum" } else { "count" }),
      parts,
      edits,
    )
  }
  if !visible {
    for position in 0..<table.columns.length() {
      let address = Address::{
        row: table.range.bottom,
        column: table.range.left + position,
      }.name()
      let cell = current.cells.get(address)
      let expected = table_total_content(table, position)
      if !same_table_content(cell, expected) {
        let setting = if cell.bind(cell => cell.formula) is Some(formula) {
          Formula(formula)
        } else {
          match cell.map(cell => cell.value).unwrap_or(Blank) {
            Blank => Clear
            Text(text) => Label(text)
            value => Formula(value.display())
          }
        }
        self.write_table_total(table, position, setting, parts, edits)
      }
      updates[address] = { value: Blank, formula: None, keep_shared: false, }
    }
    if edits.is_empty() &&
      table.columns.all(column => {
        column.total_function is None &&
        column.total_label is None &&
        column.total_formula is None
      }) {
      self.write_table_total(
        table,
        table.columns.length() - 1,
        Clear,
        parts,
        edits,
      )
    }
  }
  let source = parts
    .get(table.part)
    .unwrap_or_else(() => self.part_xml(table.part))
  let tree = table_edit_tree(table, source)
  let root = tree.root("table")
  let changes = metadata_changes(root, [
    ("ref", range.name()),
    ("totalsRowCount", if visible { "1" } else { "0" }),
    ("totalsRowShown", if visible { "1" } else { "0" }),
  ])
  if tree.one(root.id, "autoFilter") is Some(filter) {
    changes.append(
      metadata_changes(filter, [
        (
          "ref",
          Range::{
            ..range,
            bottom: range.bottom - (if visible { 1 } else { 0 }),
          }.name(),
        ),
      ]),
    )
  }
  let (document, edit) = source.edit_source(changes)
  parts[table.part] = document
  edits.push((table.part, edit))
  if visible {
    let candidate = read_table(current, table.part, document)
    for position in 0..<table.columns.length() {
      let address = Address::{
        row: range.bottom,
        column: range.left + position,
      }.name()
      let content = table_total_content(candidate, position)
      if !same_table_content(current.cells.get(address), content) {
        updates[address] = content
      }
    }
  }
  self.finish_table_edit(table, parts, edits, updates)
}
