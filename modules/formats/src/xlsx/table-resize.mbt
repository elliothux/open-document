///|
fn Session::resize_table(
  self : Session,
  sheet : String,
  id : Int,
  range : String,
) -> Json raise @failure.Failure {
  let reason = self.sheet_rename_reason(structure=false, tables=true)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let tables = self.table_definitions(self.sheets, self.workbook, self.parts)
  guard tables
    .iter()
    .find_first(table => table.sheet == sheet && table.id == id)
    is Some(table) else {
    @failure.reject(
      "invalid-operation", "Table is outside the selected worksheet",
    )
  }
  let index = self.sheet_index(sheet)
  let current = self.sheets[index]
  guard table.reason.is_empty() &&
    table.style_reason.is_empty() &&
    !current.locked &&
    current.state == "visible" else {
    @failure.reject("protected-content", "Table or worksheet is protected")
  }
  let range = Range::parse(range)
  if range == table.range {
    return self.query()
  }
  let filter_plan = self.resize_filter_plan(table, range)
  guard range.top == table.range.top &&
    range.intersects(table.range) &&
    range.bottom - range.top + 1 > table.headers + table.totals &&
    !current.merges.any(merge => merge.intersects(range)) &&
    !tables.any(other => {
      other.part != table.part &&
      other.sheet == sheet &&
      other.range.intersects(range)
    }) &&
    !read_filter(current)
    .map(filter => filter.bounds.intersects(range))
    .unwrap_or(false) else {
    @failure.reject(
      "invalid-operation", "Table range must keep its first row and data without overlapping tables, merges or filters",
    )
  }
  let width = range.right - range.left + 1
  guard tables
    .iter()
    .fold(init=width, (sum, other) => {
      sum + (if other.part == table.part { 0 } else { other.columns.length() })
    }) <=
    4096 else {
    @failure.reject("limit-exceeded", "Workbook table columns exceed budget")
  }
  let source = self.part_xml(table.part)
  let tree = Tree::new(source)
  let root = tree.root("table")
  let filter = tree.one(root.id, "autoFilter")
  self.check_sort_metadata(tree, table=true)
  let work : FormulaWork = {
    remaining: 1048576,
    date1904: self.date1904,
    origin: self.focus,
    names: self.formula_names(),
  }
  for cell in current.cells.values() {
    if cell.group is Some(_) &&
      cell.formula is Some(formula) &&
      table.range.contains(cell.address) != range.contains(cell.address) {
      work.spend(amount=formula.length() + 1)
      guard !local_table_tokens(formula_tokens(formula)) else {
        @failure.reject(
          "protected-content", "Shared local table references cross the resized boundary",
        )
      }
    }
  }
  let parent = tree.one(root.id, "tableColumns").unwrap()
  guard parent.attributes.all(attribute => {
      attribute.uri.is_empty() && attribute.name == "count"
    }) &&
    tree.children
    .get(parent.id)
    .unwrap_or([])
    .all(node => node.uri == spreadsheet_uri && node.name == "tableColumn") &&
    filter
    .map(node => {
      table.filter is Some(_) ||
      (
        node.attributes.all(attribute => {
          attribute.uri.is_empty() && attribute.name == "ref"
        }) &&
        tree.children.get(node.id).unwrap_or([]).is_empty()
      )
    })
    .unwrap_or(true) else {
    @failure.reject(
      "protected-content", "Unknown table column or filter metadata requires range editing support",
    )
  }
  let nodes = tree.all(parent.id, "tableColumn")
  let retained : Array[String] = []
  for offset, column in table.columns {
    if table.range.left + offset >= range.left &&
      table.range.left + offset <= range.right {
      retained.push(column.name)
    }
  }
  let removed = table.columns
    .filter(column => !retained.contains(column.name))
    .map(column => column.name.to_upper())
  let added : Array[Int] = []
  let labels : Array[String] = []
  let seen : Map[String, Bool] = Map([])
  for column in table.columns {
    seen[column.name.to_upper()] = true
  }
  for column in range.left..<=range.right {
    if column >= table.range.left && column <= table.range.right {
      continue
    }
    added.push(column)
    let address = Address::{
      row: (range.top - (if table.headers == 0 { 1 } else { 0 })).max(1),
      column,
    }.name()
    let cell = if table.headers == 0 && range.top == 1 {
      None
    } else {
      current.cells.get(address)
    }
    guard cell
      .map(cell => cell.read_only.is_empty() && cell.group is None)
      .unwrap_or(true) else {
      @failure.reject(
        "protected-content", "New table header source requires editing support",
      )
    }
    let value = self.calculation
      .bind(calculation => calculation.values.get((index, address)))
      .unwrap_or(cell.map(cell => cell.value).unwrap_or(Blank))
    let label = if table.headers == 0 && range.top == 1 {
      ""
    } else {
      value.display()
    }
    let label = if seen.contains(label.to_upper()) { "" } else { label }
    if !label.is_empty() {
      seen[label.to_upper()] = true
    }
    labels.push(label)
  }
  let labels = table_header_names(
    labels,
    table.columns.map(column => column.name),
    retained
    .iter()
    .fold(init=table.name.length(), (sum, name) => sum + name.length()),
  )
  let updates : Map[String, CellContent] = Map([])
  let ids : Map[Int, Bool] = Map([])
  for column in table.columns {
    ids[column.id] = true
  }
  let before = StringBuilder()
  let after = StringBuilder()
  for offset, column in added {
    let id = for id in 1..<=8193 {
      if !ids.contains(id) {
        break id
      }
    } nobreak {
      @failure.reject("limit-exceeded", "Table column identities exhausted")
    }
    ids[id] = true
    let markup = "<od:tableColumn xmlns:od=\"\{spreadsheet_uri}\" id=\"\{id}\" name=\"\{escaped_attribute(encoded_text(labels[offset]))}\"/>"
    if column < table.range.left {
      before.write_string(markup)
    } else {
      after.write_string(markup)
    }
    if table.headers == 1 {
      updates[Address::{ row: range.top, column, }.name()] = {
        value: Text(labels[offset]),
        formula: None,
        keep_shared: false,
      }
    }
  }
  if table.totals == 1 && range.bottom != table.range.bottom {
    for column in range.left..<=range.right {
      let target = Address::{ row: range.bottom, column, }.name()
      guard current.cells
        .get(target)
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
      let cell = current.cells.get(
        Address::{ row: table.range.bottom, column, }.name(),
      )
      if column >= table.range.left && column <= table.range.right {
        guard cell
          .map(cell => cell.read_only.is_empty() && cell.group is None)
          .unwrap_or(true) else {
          @failure.reject(
            "protected-content", "Totals source requires editing support",
          )
        }
        updates[target] = {
          value: cell.map(cell => cell.value).unwrap_or(Blank),
          formula: cell.bind(cell => cell.formula),
          keep_shared: false,
        }
      }
    }
    for column in table.range.left..<=table.range.right {
      updates[Address::{ row: table.range.bottom, column, }.name()] = {
        value: Blank,
        formula: None,
        keep_shared: false,
      }
    }
  }
  let new_rows = (range.bottom - table.range.bottom).max(0)
  let calculated : Array[Int] = []
  for offset, column in table.columns {
    if column.formula is Some(_) &&
      table.range.left + offset >= range.left &&
      table.range.left + offset <= range.right {
      calculated.push(offset)
    }
  }
  guard new_rows.to_int64() * calculated.length().to_int64() <= 4096 else {
    @failure.reject(
      "limit-exceeded", "Calculated table expansion exceeds 4096 cells",
    )
  }
  for offset in calculated {
    let formula = tree.one(nodes[offset].id, "calculatedColumnFormula").unwrap().text
    let expression = parse_formula(formula)
    for
      row in (table.range.bottom - table.totals + 1)..<=(range.bottom -
      table.totals) {
      let address = Address::{ row, column: table.range.left + offset, }.name()
      let cell = current.cells.get(address)
      let content = updates
        .get(address)
        .unwrap_or({
          value: cell.map(cell => cell.value).unwrap_or(Blank),
          formula: cell.bind(cell => cell.formula),
          keep_shared: false,
        })
      if content.value == Blank && content.formula is None {
        guard cell
          .map(cell => cell.read_only.is_empty() && cell.group is None)
          .unwrap_or(true) else {
          @failure.reject(
            "protected-content", "Calculated table expansion crosses protected source",
          )
        }
        let formula = expression.source(
          rows=row - table.range.top - table.headers,
          invalid_ref=true,
        )
        work.spend(amount=formula.length() + 1)
        updates[address] = {
          value: Blank,
          formula: Some(formula),
          keep_shared: false,
        }
      }
    }
  }
  let changes = metadata_changes(root, [("ref", range.name())])
  if tree.one(root.id, "sortState") is Some(sort) {
    changes.append(
      resized_sort_state(tree, sort, {
        ..range,
        top: range.top + table.headers,
        bottom: range.bottom - table.totals,
      }),
    )
  }
  if filter is Some(filter) {
    if tree.one(filter.id, "sortState") is Some(sort) {
      changes.append(
        resized_sort_state(tree, sort, {
          ..range,
          bottom: range.bottom - table.totals,
        }),
      )
    }
    changes.append(
      metadata_changes(filter, [
        ("ref", Range::{ ..range, bottom: range.bottom - table.totals, }.name()),
      ]),
    )
  }
  changes.append(metadata_changes(parent, [("count", width.to_string())]))
  for offset, node in nodes {
    if table.range.left + offset < range.left ||
      table.range.left + offset > range.right {
      changes.push(sheet_node_removal(tree, node))
    }
  }
  if !before.to_string().is_empty() {
    changes.push({
      node: parent.id,
      offset: nodes[0].start - parent.start,
      length: 0,
      xml: before.to_string(),
    })
  }
  if !after.to_string().is_empty() {
    changes.push(insertion(parent, after.to_string()))
  }
  let (document, edit) = source.edit_source(changes)
  let parts = self.parts.copy()
  parts[table.part] = document
  let edits : Array[(String, @xml.Edit)] = [(table.part, edit)]
  let sheets = self.sheets.copy()
  if !updates.is_empty() {
    let (document, edit) = current.prepare(updates)
    sheets[index] = Sheet::read(
      sheet,
      current.name,
      current.state,
      document,
      self.strings,
      self.styles.length(),
    )
    edits.push((sheet, edit))
  }
  let workbook_changes = resized_table_references(
    self.workbook,
    table,
    range,
    removed,
    self.main,
    work,
  )
  let workbook = if workbook_changes.is_empty() {
    self.workbook
  } else {
    let (document, edit) = self.workbook.edit_source(workbook_changes)
    edits.push((self.main, edit))
    document
  }
  for original in tables {
    let source = parts
      .get(original.part)
      .unwrap_or_else(() => self.part_xml(original.part))
    let changes = resized_table_references(
      source,
      table,
      range,
      removed,
      original.part,
      work,
    )
    if !changes.is_empty() {
      let (document, edit) = source.edit_source(changes)
      parts[original.part] = document
      edits.push((original.part, edit))
    }
  }
  for position, current in sheets {
    let changes = resized_table_references(
      current.document,
      table,
      range,
      removed,
      current.id,
      work,
    )
    if current.id == sheet {
      changes.append(resized_table_conditions(current.document, table, range))
    }
    if !changes.is_empty() {
      let (document, edit) = current.document.edit_source(changes)
      sheets[position] = Sheet::read(
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
  if filter_plan is Some(plan) {
    let current = sheets[index]
    let document = self.write_filter_plan(current, plan, parts, edits)
    sheets[index] = Sheet::read(
      current.id,
      current.name,
      current.state,
      document,
      self.strings,
      self.styles.length(),
    )
  }
  let mut calculation = self.calculate(sheets, None, [], workbook, parts~)
  if filter_plan is Some(plan) {
    let candidate : Session = {
      ..self,
      sheets,
      workbook,
      parts,
      calculation: Some(calculation),
    }
    calculation = candidate.reapply_candidate_filters(
      index,
      candidate.sheet_filters(sheets[index], parts),
      plan.targets,
      sheets,
      workbook,
      calculation,
      parts,
      edits,
    )
  }
  self.validate_inputs(
    sheets,
    calculation,
    Map([(index, updates.keys().to_array())]),
    false,
  )
  edits.append(self.cache_edits(sheets, calculation))
  self.commit(sheets, workbook, calculation, edits, (sheet, range), parts~, table_edits=[
    table.part,
  ])
  self.query()
}
