///|
fn pivot_table_name(source : String) -> String {
  if source.has_suffix("[]") {
    source[:source.length() - 2].to_owned()
  } else {
    source
  }
}

///|
fn pivot_table_range(table : StructuredTable) -> Range raise @failure.Failure {
  guard table.headers == 1 &&
    table.range.bottom - table.totals > table.range.top else {
    @failure.reject(
      "protected-content", "A pivot table source requires a header and data rows",
    )
  }
  { ..table.range, bottom: table.range.bottom - table.totals, }
}

///|
fn Session::pivot_source(
  self : Session,
  settings : PivotSettings,
) -> (Range, String?) raise @failure.Failure {
  let name = pivot_table_name(settings.source).to_upper()
  let table = self
    .table_definitions(self.sheets, self.workbook, self.parts)
    .iter()
    .find_first(table => table.name.to_upper() == name)
  if table is Some(table) {
    guard table.sheet == settings.sourceSheet else {
      @failure.reject(
        "invalid-operation", "Pivot source table belongs to another worksheet",
      )
    }
    let range = pivot_table_range(table)
    (settings.validate(source=Some(range)), Some(table.name))
  } else {
    (settings.validate(), None)
  }
}

///|
fn Session::worksheet_pivot_source(
  self : Session,
  node : @xml.Node,
) -> (String?, Range?, String?) raise @failure.Failure {
  if node.attribute("name") is Some(name) {
    guard node.attribute("ref") is None else {
      @failure.reject(
        "protected-content", "A pivot source cannot combine a table name and range",
      )
    }
    let name = pivot_table_name(name)
    let table = self
      .table_definitions(self.sheets, self.workbook, self.parts)
      .iter()
      .find_first(table => table.name.to_upper() == name.to_upper())
    if table is Some(table) {
      guard node
        .attribute("sheet")
        .map(name => {
          name.to_upper() ==
          self.sheets[self.sheet_index(table.sheet)].name.to_upper()
        })
        .unwrap_or(true) else {
        @failure.reject(
          "protected-content", "Pivot table and worksheet source disagree",
        )
      }
      return (
        Some(table.sheet),
        Some(pivot_table_range(table)),
        Some(table.name),
      )
    }
    return (None, None, Some(name))
  }
  let sheet = self.sheets
    .iter()
    .find_first(sheet => {
      node
      .attribute("sheet")
      .map(name => name.to_upper() == sheet.name.to_upper())
      .unwrap_or(false)
    })
    .map(sheet => sheet.id)
  (sheet, node.attribute("ref").map(Range::parse), None)
}

///|
fn Session::maintain_pivot_table_source(
  self : Session,
  pivot : PivotLocation,
  sheets : Array[Sheet],
  tables : Array[StructuredTable],
  parts : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
) -> Bool raise @failure.Failure {
  guard pivot.sourceTable is Some(name) else { return false }
  let previous = self
    .table_definitions(self.sheets, self.workbook, self.parts)
    .iter()
    .find_first(table => table.name.to_upper() == name.to_upper())
  guard previous is Some(previous) else { return false }
  let next = tables.iter().find_first(table => table.part == previous.part)
  let changed = match next {
    Some(next) => {
      let range = pivot_table_range(next)
      guard !self
        .pivot_locations()
        .any(pivot => {
          pivot.sourceTable
          .map(value => value.to_upper() == name.to_upper())
          .unwrap_or(false) &&
          pivot.sheet == next.sheet &&
          range.intersects(pivot.range)
        }) else {
        @failure.reject(
          "protected-content", "A pivot source table cannot expand into its report",
        )
      }
      range != pivot_table_range(previous) ||
      previous.columns != next.columns ||
      previous.name != next.name
    }
    None => true
  }
  if !changed {
    return false
  }
  for path in self.analysis_parts() {
    let original = parts.get(path).unwrap_or_else(() => self.part_xml(path))
    if original.nodes()[0].name != "pivotCacheDefinition" {
      continue
    }
    let tree = Tree::new(original)
    let source = tree
      .one(0, "cacheSource")
      .bind(node => tree.one(node.id, "worksheetSource"))
    guard source is Some(source) &&
      source
      .attribute("name")
      .map(value => pivot_table_name(value).to_upper() == name.to_upper())
      .unwrap_or(false) else {
      continue
    }
    let changes = metadata_changes(tree.nodes[0], [("invalid", "1")])
    match next {
      Some(next) => {
        let range = pivot_table_range(next)
        guard tree
          .all(tree.one(0, "cacheFields").unwrap().id, "cacheField")
          .filter(field => flag(field, "databaseField", fallback=true))
          .length() ==
          range.right - range.left + 1 else {
          @failure.reject(
            "protected-content", "Pivot table columns require coordinated field mapping",
          )
        }
        changes.append(metadata_changes(source, [("name", next.name)]))
      }
      None => {
        guard sheets.iter().find_first(sheet => sheet.id == previous.sheet)
          is Some(sheet) else {
          @failure.reject(
            "protected-content", "Pivot source deletion requires cache maintenance",
          )
        }
        changes.append(table_attribute_removals(original, source, ["name"]))
        changes.append(
          metadata_changes(source, [
            ("sheet", sheet.name),
            ("ref", pivot_table_range(previous).name()),
          ]),
        )
      }
    }
    if !changes.is_empty() {
      let (document, edit) = original.edit_source(join_insertions(changes))
      parts[path] = document
      edits.push((path, edit))
    }
  }
  true
}
