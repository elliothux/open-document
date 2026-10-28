///|
fn Session::copied_table_references(
  self : Session,
  source : @xml.Document,
  names : Array[(StructuredTable, String)],
) -> @xml.Document raise @failure.Failure {
  let work : FormulaWork = {
    remaining: 1048576,
    date1904: self.date1904,
    origin: self.focus,
    names: self.formula_names(),
  }
  let mut document = source
  for (table, name) in names {
    let changes = table_formula_changes(
      document,
      table,
      name,
      None,
      table.part,
      work,
    )
    if !changes.is_empty() {
      document = document.edit_source(changes).0
    }
  }
  document
}

///|
fn Session::copy_sheet_tables(
  self : Session,
  source : Sheet,
  target : Sheet,
  number : Int32,
  created : Map[String, @xml.Document],
  remapped : Map[String, String],
  types : StringBuilder,
) -> Array[(StructuredTable, String)] raise @failure.Failure {
  let tables = self.sheet_tables()
  let copied = tables.filter(table => table.sheet == source.id)
  if copied.is_empty() {
    return []
  }
  guard tables.length() + copied.length() <= 256 &&
    tables.iter().fold(init=0, (sum, table) => sum + table.columns.length()) +
    copied.iter().fold(init=0, (sum, table) => sum + table.columns.length()) <=
    4096 else {
    @failure.reject(
      "limit-exceeded", "Copied tables exceed workbook table or column budget",
    )
  }
  let ids : Map[Int32, Bool] = Map([])
  let names : Map[String, Bool] = Map([])
  for table in tables {
    ids[table.id] = true
    names[table.name.to_upper()] = true
  }
  for key in self.formula_names().sources.keys() {
    names[key.1.to_upper()] = true
  }
  let directory = self.main.split("/").map(part => part.to_owned()).to_array()
  ignore(directory.pop())
  let prefix = if directory.is_empty() { "" } else { directory.join("/") + "/" }
  let mappings : Array[(StructuredTable, String)] = []
  let drafts : Array[(String, @xml.Document)] = []
  let mut bytes = target.document.source().length().to_int64() * 2 +
    created
    .values()
    .fold(init=0L, (sum, document) => {
      sum + document.source().length().to_int64() * 2
    })
  for table in copied {
    let id = for id in 1..<=257 {
      if !ids.contains(id) {
        break id
      }
    } nobreak {
      @failure.reject("limit-exceeded", "Copied table identities exhausted")
    }
    ids[id] = true
    let name = for index in 1..<=8193 {
      let name = "Table\{index}"
      if !names.contains(name.to_upper()) {
        break name
      }
    } nobreak {
      @failure.reject("limit-exceeded", "Copied table names exhausted")
    }
    names[name.to_upper()] = true
    let part = for index in 0..<=self.budget.entries {
      let part = prefix + "tables/odSheet\{number}-\{index}.xml"
      if !self.opc.names.contains(part.to_lower()) &&
        !self.parts.contains(part) &&
        !created.contains(part) &&
        !drafts.any(draft => draft.0 == part) &&
        !self.opc.names.contains(workbook_relations(part).to_lower()) &&
        !self.parts.contains(workbook_relations(part)) {
        break part
      }
    } nobreak {
      @failure.reject("limit-exceeded", "Copied table parts exhausted")
    }
    let original = self.part_xml(table.part)
    bytes += original.source().length().to_int64() * 2
    guard bytes <= 4194304L else {
      @failure.reject(
        "limit-exceeded", "Copied table sources exceed history budget",
      )
    }
    let tree = Tree::new(original)
    let changes = metadata_changes(tree.root("table"), [
      ("id", id.to_string()),
      ("name", name),
      ("displayName", name),
    ])
    changes.append(
      sheet_reference_changes(original, source.name, Some(target.name)),
    )
    let document = original.edit_source(changes).0
    drafts.push((part, document))
    mappings.push((table, name))
    remapped[table.part] = part
  }
  let work : FormulaWork = {
    remaining: 1048576,
    date1904: self.date1904,
    origin: self.focus,
    names: self.formula_names(),
  }
  for (part, source) in drafts {
    let mut source = source
    for (table, name) in mappings {
      let changes = table_formula_changes(
        source,
        table,
        name,
        None,
        table.part,
        work,
      )
      if !changes.is_empty() {
        source = source.edit_source(changes).0
      }
    }
    created[part] = @xml.Document::parse(
      source.bytes(),
      part,
      self.budget.xml_depth,
      self.budget.entry_bytes,
    )
    types.write_string(
      "<od:Override xmlns:od=\"http://schemas.openxmlformats.org/package/2006/content-types\" PartName=\"/\{escaped_attribute(part)}\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.table+xml\"/>",
    )
  }
  mappings
}
