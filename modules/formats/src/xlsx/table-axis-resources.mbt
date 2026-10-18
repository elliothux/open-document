///|
fn Session::axis_table_resources(
  self : Session,
  sheet : Sheet,
  plans : Array[AxisTable],
  parts : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
  removed : Map[String, @xml.Document],
) -> @xml.Document raise @failure.Failure {
  let deleted = plans
    .filter(plan => plan.after is None)
    .map(plan => plan.before.part)
  if deleted.is_empty() {
    return sheet.document
  }
  let links = self.relationships()
  let ids : Array[String] = []
  for part in deleted {
    guard !links.any(link => {
        link.owner == part ||
        (
          link.target == part &&
          (
            link.owner != sheet.id ||
            link.external ||
            link.kind != relationship_uri + "table"
          )
        )
      }) &&
      !self.parts.contains(workbook_relations(part)) &&
      !self.opc.names.contains(workbook_relations(part).to_lower()) else {
      @failure.reject(
        "protected-content", "Unknown table resource ownership prevents deletion",
      )
    }
    removed[part] = self.part_xml(part)
    parts.remove(part)
    for link in links {
      if link.owner == sheet.id && link.target == part && !link.external {
        ids.push(link.id)
      }
    }
  }
  for path in [workbook_relations(sheet.id), "[Content_Types].xml"] {
    let source = parts.get(path).unwrap_or_else(() => self.part_xml(path))
    let tree = Tree::new(source)
    let root = source.nodes()[0]
    let changes = source
      .nodes()
      .iter()
      .filter(node => {
        node.parent == root.id &&
        (if path == "[Content_Types].xml" {
          node
          .attribute("PartName")
          .map(name => {
            name.has_prefix("/") &&
            deleted.any(part => {
              part.to_lower() == name[1:].to_owned().to_lower()
            })
          })
          .unwrap_or(false)
        } else {
          node.attribute("Id").map(id => ids.contains(id)).unwrap_or(false)
        })
      })
      .map(node => sheet_node_removal(tree, node))
      .collect()
    if !changes.is_empty() {
      let (document, edit) = source.edit_source(changes)
      parts[path] = document
      edits.push((path, edit))
    }
  }
  let source = sheet.document
  let tree = Tree::new(source)
  let parent = tree.one(tree.root("worksheet").id, "tableParts").unwrap()
  let nodes = tree.all(parent.id, "tablePart")
  let selected = nodes.filter(node => {
    node.attributes.any(attribute => {
      attribute.name == "id" &&
      attribute.uri ==
      relationship_uri[:relationship_uri.length() - 1].to_owned() &&
      ids.contains(attribute.value)
    })
  })
  guard selected.length() == deleted.length() else {
    @failure.reject("malformed-xlsx", "Table ownership references do not match")
  }
  let changes = if selected.length() == nodes.length() {
    [sheet_node_removal(tree, parent)]
  } else {
    let changes = selected.map(node => sheet_node_removal(tree, node))
    changes.append(
      metadata_changes(parent, [
        ("count", (nodes.length() - selected.length()).to_string()),
      ]),
    )
    changes
  }
  let (document, edit) = source.edit_source(changes)
  edits.push((sheet.id, edit))
  document
}

///|
fn Session::table_reference_removals(
  self : Session,
  sheets : Array[Sheet],
  workbook : @xml.Document,
  changes : Array[(StructuredTable, Array[String], Bool)],
  tables : Array[StructuredTable],
  parts : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
) -> @xml.Document raise @failure.Failure {
  let work : FormulaWork = {
    remaining: 1048576,
    date1904: self.date1904,
    origin: self.focus,
    names: self.formula_names(),
  }
  let mut workbook = workbook
  for (table, removed, deleted) in changes {
    let changes = resized_table_references(
      workbook,
      table,
      table.range,
      removed,
      self.main,
      work,
      deleted~,
    )
    if !changes.is_empty() {
      let (document, edit) = workbook.edit_source(changes)
      workbook = document
      edits.push((self.main, edit))
    }
    for after in tables {
      let source = parts
        .get(after.part)
        .unwrap_or_else(() => self.part_xml(after.part))
      let changes = resized_table_references(
        source,
        table,
        table.range,
        removed,
        after.part,
        work,
        deleted~,
      )
      if !changes.is_empty() {
        let (document, edit) = source.edit_source(changes)
        parts[after.part] = document
        edits.push((after.part, edit))
      }
    }
    for index, current in sheets {
      let changes = resized_table_references(
        current.document,
        table,
        table.range,
        removed,
        current.id,
        work,
        deleted~,
      )
      if !changes.is_empty() {
        let (document, edit) = current.document.edit_source(changes)
        sheets[index] = Sheet::read(
          current.id,
          current.name,
          current.state,
          document,
          self.strings,
          self.styles.length(),
        )
        edits.push((current.id, edit))
      }
    }
  }
  workbook
}

///|
fn Session::axis_table_cells(
  self : Session,
  sheet : Sheet,
  plans : Array[AxisTable],
  change : AxisChange,
  edits : Array[(String, @xml.Edit)],
) -> (Sheet, Array[String]) raise @failure.Failure {
  let updates : Map[String, CellContent] = Map([])
  let work : FormulaWork = {
    remaining: 1048576,
    date1904: self.date1904,
    origin: self.focus,
    names: self.formula_names(),
  }
  for plan in plans {
    guard plan.after is Some(table) && table.sheet == sheet.id else { continue }
    if change.band is None &&
      !change.rows &&
      change.insert &&
      change.first > plan.before.range.left &&
      change.first <= plan.before.range.right {
      if table.headers == 1 {
        for column in change.first..<(change.first + change.count) {
          let address = Address::{ row: table.range.top, column, }.name()
          updates[address] = {
            value: Text(table.columns[column - table.range.left].name),
            formula: None,
            keep_shared: false,
          }
        }
      }
    }
    if change.rows &&
      change.insert &&
      table.range != plan.before.range &&
      table.range.top == plan.before.range.top {
      let first = change.first.max(table.range.top + table.headers)
      let last = (change.first + change.count - 1).min(
        table.range.bottom - table.totals,
      )
      if first > last {
        continue
      }
      for position, column in table.columns {
        guard column.formula is Some(formula) else { continue }
        guard last - first + 1 <= 4096 - updates.length() else {
          @failure.reject(
            "limit-exceeded", "Inserted calculated table cells exceed 4096",
          )
        }
        let expression = parse_formula(formula)
        for row in first..<=last {
          let formula = expression.source(
            rows=row - table.range.top - table.headers,
            invalid_ref=true,
          )
          work.spend(amount=formula.length() + 1)
          updates[Address::{ row, column: table.range.left + position, }.name()] = {
            value: Blank,
            formula: Some(formula),
            keep_shared: false,
          }
        }
      }
    }
  }
  if updates.is_empty() {
    return (sheet, [])
  }
  for address in updates.keys() {
    guard sheet.cells
      .get(address)
      .map(cell => {
        cell.value == Blank &&
        cell.formula is None &&
        cell.read_only.is_empty() &&
        cell.group is None
      })
      .unwrap_or(true) else {
      @failure.reject(
        "protected-content", "Inserted table cells contain existing data or protected source",
      )
    }
  }
  let (document, edit) = sheet.prepare(updates)
  edits.push((sheet.id, edit))
  (
    Sheet::read(
      sheet.id,
      sheet.name,
      sheet.state,
      document,
      self.strings,
      self.styles.length(),
    ),
    updates.keys().to_array(),
  )
}
