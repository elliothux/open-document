///|
fn Session::sorting_table(
  self : Session,
  sheet : String,
  range : Range,
  rows : Bool,
  sparklines~ : Bool = false,
) -> StructuredTable? raise @failure.Failure {
  let tables = self
    .table_definitions(self.sheets, self.workbook, self.parts)
    .filter(table => table.sheet == sheet && table.range.intersects(range))
  if tables.is_empty() {
    return None
  }
  guard tables is [table] && table.range.covers(range) && rows else {
    @failure.reject(
      "protected-content", "Tables sort whole data rows within a single table",
    )
  }
  guard table.range.bottom - table.totals >= table.range.top + table.headers else {
    @failure.reject("invalid-operation", "Table sorting requires data rows")
  }
  Some(self.table_for_edit(sheet, table.id, sparklines~))
}

///|
fn Session::write_table_sort(
  self : Session,
  table : StructuredTable,
  state : StoredSort,
  parts : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
) -> Unit raise @failure.Failure {
  let source = parts
    .get(table.part)
    .unwrap_or_else(() => self.part_xml(table.part))
  let (document, edit) = write_sort_state(source, state, table=true)
  edits.push((table.part, edit))
  let tree = Tree::new(document)
  let nested = tree
    .one(tree.root("table").id, "autoFilter")
    .bind(filter => tree.one(filter.id, "sortState"))
  let document = if nested is Some(node) {
    let (document, edit) = document.edit_source([sheet_node_removal(tree, node)])
    edits.push((table.part, edit))
    document
  } else {
    document
  }
  parts[table.part] = document
}
