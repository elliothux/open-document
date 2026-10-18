///|
fn Session::sheet_tables(
  self : Session,
) -> Array[StructuredTable] raise @failure.Failure {
  let tables = self.table_definitions(self.sheets, self.workbook, self.parts)
  let links = self.relationships()
  for table in tables {
    guard table.reason.is_empty() && table.style_reason.is_empty() else {
      @failure.reject(
        "protected-content", "Table source requires worksheet resource support",
      )
    }
    let tree = table_edit_tree(table, self.part_xml(table.part))
    self.check_sort_metadata(tree, table=true)
    guard !links.any(link => {
        link.owner == table.part ||
        (
          link.target == table.part &&
          (
            link.owner != table.sheet ||
            link.external ||
            link.kind != relationship_uri + "table"
          )
        )
      }) &&
      !self.parts.contains(workbook_relations(table.part)) &&
      !self.opc.names.contains(workbook_relations(table.part).to_lower()) else {
      @failure.reject(
        "protected-content", "Unknown table resource ownership prevents worksheet editing",
      )
    }
  }
  tables
}

///|
fn Session::sheet_table_references(
  self : Session,
  tables : Array[StructuredTable],
  old : String,
  name : String?,
  parts : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
) -> Unit raise @failure.Failure {
  for table in tables {
    if name is None && self.sheets[self.sheet_index(table.sheet)].name == old {
      continue
    }
    let source = parts
      .get(table.part)
      .unwrap_or_else(() => self.part_xml(table.part))
    let changes = sheet_reference_changes(source, old, name)
    if !changes.is_empty() {
      let (document, edit) = source.edit_source(changes)
      parts[table.part] = document
      edits.push((table.part, edit))
    }
  }
}
