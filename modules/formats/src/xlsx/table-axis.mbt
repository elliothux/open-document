///|
priv struct AxisTable {
  before : StructuredTable
  after : StructuredTable?
  removed : Array[String]
}

///|
fn table_axis_formula(
  text : String,
  table : StructuredTable,
  sheet : String,
  target : String,
  change : AxisChange,
  calculated : Bool,
) -> String raise @failure.Failure {
  if calculated && sheet == target && change.rows && change.band is None {
    let first = table.range.top + table.headers
    let anchor = if !change.insert &&
      first >= change.first &&
      first < change.first + change.count {
      change.first + change.count
    } else {
      first
    }
    let moved = change
      .address({ row: anchor, column: table.range.left, })
      .map(address => address.row)
      .unwrap_or(anchor)
    let next = change.range(table.range).unwrap()
    let text = if anchor == first {
      text
    } else {
      parse_formula(text).source(rows=anchor - first, invalid_ref=true)
    }
    let text = axis_formula(text, Some(sheet), target, change)
    let offset = next.top + table.headers - moved
    if offset == 0 {
      text
    } else {
      parse_formula(text).source(rows=offset, invalid_ref=true)
    }
  } else {
    axis_formula(text, Some(sheet), target, change)
  }
}

///|
fn Session::axis_tables(
  self : Session,
  sheet : Sheet,
  change : AxisChange,
  parts : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
) -> Array[AxisTable] raise @failure.Failure {
  let tables = self.table_definitions(self.sheets, self.workbook, self.parts)
  let plans : Array[AxisTable] = []
  let work : FormulaWork = {
    remaining: 1048576,
    date1904: self.date1904,
    origin: self.focus,
    names: self.formula_names(),
  }
  let mut count = 0
  for table in tables {
    let own = table.sheet == sheet.id
    let range = if own { change.range(table.range) } else { Some(table.range) }
    if own && change.band is Some((first, last)) {
      let (low, high) = if change.rows {
        (table.range.left, table.range.right)
      } else {
        (table.range.top, table.range.bottom)
      }
      guard high < first ||
        low > last ||
        (if change.rows { table.range.bottom } else { table.range.right }) <
        change.first else {
        @failure.reject(
          "protected-content", "Partial cell shifts through tables require table-aware editing",
        )
      }
    }
    if own && change.insert && change.band is None {
      let last = if change.rows {
        table.range.bottom
      } else {
        table.range.right
      }
      guard last < change.first || last <= change.limit() - change.count else {
        @failure.reject(
          "invalid-operation", "Insertion would discard table rows or columns",
        )
      }
    }
    let source = self.part_xml(table.part)
    let tree = table_edit_tree(table, source)
    guard table.reason.is_empty() && table.style_reason.is_empty() else {
      @failure.reject(
        "protected-content", "Table source requires structural editing support",
      )
    }
    if range is None {
      plans.push({
        before: table,
        after: None,
        removed: table.columns.map(column => column.name.to_upper()),
      })
      continue
    }
    let range = range.unwrap()
    if own &&
      change.band is None &&
      change.rows &&
      !change.insert &&
      change.first <= table.range.top &&
      change.first + change.count > table.range.top {
      @failure.reject(
        "protected-content", "Deleting a table header requires deleting the whole table",
      )
    }
    let totals = if own &&
      change.rows &&
      !change.insert &&
      table.totals == 1 &&
      change.address({ row: table.range.bottom, column: table.range.left, })
      is None {
      0
    } else {
      table.totals
    }
    guard range.bottom - range.top == table.range.bottom - table.range.top ||
      range.bottom - range.top + 1 > table.headers + totals else {
      @failure.reject(
        "invalid-operation", "Structural editing must retain a table data row",
      )
    }
    let root = tree.root("table")
    let parent = tree.one(root.id, "tableColumns").unwrap()
    let nodes = tree.all(parent.id, "tableColumn")
    let changes = metadata_changes(root, [("ref", range.name())])
    if own &&
      change.band is None &&
      tree.one(root.id, "sortState") is Some(sort) {
      let (updates, _) = axis_sort_state(tree, sort, change)
      changes.append(updates)
    }
    if totals != table.totals {
      changes.append(
        metadata_changes(root, [
          ("totalsRowCount", "0"),
          ("totalsRowShown", "0"),
        ]),
      )
    }
    if tree.one(root.id, "autoFilter") is Some(filter) {
      if own &&
        change.band is None &&
        tree.one(filter.id, "sortState") is Some(sort) {
        let (updates, _) = axis_sort_state(tree, sort, change)
        changes.append(updates)
      }
      changes.append(
        metadata_changes(filter, [
          ("ref", Range::{ ..range, bottom: range.bottom - totals, }.name()),
        ]),
      )
    }
    let columns : Array[TableColumn] = []
    let removed : Array[String] = []
    let labels = if own &&
      change.band is None &&
      !change.rows &&
      change.insert &&
      change.first > table.range.left &&
      change.first <= table.range.right {
      table_header_names(
        Array::make(change.count, ""),
        table.columns.map(column => column.name),
        table.columns
        .iter()
        .fold(init=table.name.length(), (sum, column) => {
          sum + column.name.length()
        }),
      )
    } else {
      []
    }
    let used : Map[Int, Bool] = Map([])
    for column in table.columns {
      used[column.id] = true
    }
    for position, column in table.columns {
      let old = Address::{
        row: table.range.top,
        column: table.range.left + position,
      }
      if own && !change.rows && change.address(old) is None {
        removed.push(column.name.to_upper())
        changes.push(sheet_node_removal(tree, nodes[position]))
        continue
      }
      if !labels.is_empty() && old.column == change.first {
        let markup = StringBuilder()
        for label in labels {
          let id = for id in 1..<=8193 {
            if !used.contains(id) {
              break id
            }
          } nobreak {
            @failure.reject(
              "limit-exceeded", "Table column identities exhausted",
            )
          }
          used[id] = true
          columns.push({
            id,
            name: label,
            formula: None,
            total_function: None,
            total_label: None,
            total_formula: None,
          })
          markup <+
            "<od:tableColumn xmlns:od=\"\{spreadsheet_uri}\" id=\"\{id}\" name=\"\{escaped_attribute(encoded_text(label))}\"/>"
        }
        changes.push({
          node: parent.id,
          offset: nodes[position].start - parent.start,
          length: 0,
          xml: markup.to_string(),
        })
      }
      let owner = self.sheets[self.sheet_index(table.sheet)].name
      let formula = column.formula.map(text => {
        work.spend(amount=text.length() + 1)
        table_axis_formula(text, table, owner, sheet.name, change, true)
      })
      let total_formula = column.total_formula.map(text => {
        work.spend(amount=text.length() + 1)
        table_axis_formula(text, table, owner, sheet.name, change, false)
      })
      for
        (kind, text) in [
          ("calculatedColumnFormula", formula),
          ("totalsRowFormula", total_formula),
        ] {
        if text is Some(text) {
          changes.append(
            table_formula_change(tree, nodes[position], kind, Some(text)),
          )
        }
      }
      columns.push({ ..column, formula, total_formula, })
    }
    count += columns.length()
    guard count <= 4096 else {
      @failure.reject("limit-exceeded", "Workbook table columns exceed budget")
    }
    changes.append(
      metadata_changes(parent, [("count", columns.length().to_string())]),
    )
    if !changes.is_empty() {
      let (document, edit) = source.edit_source(changes)
      parts[table.part] = document
      edits.push((table.part, edit))
    }
    plans.push({
      before: table,
      after: Some({ ..table, range, totals, columns, }),
      removed,
    })
  }
  plans
}
