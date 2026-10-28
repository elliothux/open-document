///|
fn table_reference_formula(
  text : String,
  table : StructuredTable,
  in_table : Bool,
  name : String,
  column : Int32?,
) -> String raise @failure.Failure {
  let spans : Array[(Int32, Int32)] = []
  let tokens = formula_tokens(text, spans~)
  let changes : Array[(Int32, Int32, String)] = []
  for index, token in tokens {
    match token {
      Word(word) if word.to_upper() == table.name.to_upper() &&
        !(tokens.get(index + 1) is Some(Operator("!" | "("))) &&
        !(index > 0 && tokens[index - 1] is Operator("!")) =>
        if column is None {
          changes.push((spans[index].0, spans[index].1, name))
        }
      Brackets(selector) if column is Some(column) => {
        let bound = if index > 0 && tokens[index - 1] is Word(word) {
          word.to_upper() == table.name.to_upper()
        } else {
          in_table
        }
        if !bound {
          continue
        }
        for (heading, first, last) in table_selector(selector).columns {
          if heading.to_upper() == table.columns[column].name.to_upper() {
            changes.push(
              (
                spans[index].0 + first,
                spans[index].0 + last,
                structured_escape(name),
              ),
            )
          }
        }
      }
      _ => ()
    }
  }
  let out = StringBuilder()
  let mut cursor = 0
  for (first, last, replacement) in changes {
    out.write_view(text[cursor:first])
    out.write_string(replacement)
    cursor = last
  }
  out.write_view(text[cursor:])
  let result = out.to_string()
  guard result.length() <= 8192 else {
    @failure.reject("limit-exceeded", "Renamed table formula exceeds budget")
  }
  result
}

///|
fn table_formula_changes(
  document : @xml.Document,
  table : StructuredTable,
  name : String,
  column : Int32?,
  owner : String,
  work : FormulaWork,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let tree = Tree::new(document)
  let result : Array[@xml.SourceChange] = []
  for node in document.nodes() {
    if node.uri != spreadsheet_uri ||
      ![
        "f", "formula", "formula1", "formula2", "definedName", "calculatedColumnFormula",
        "totalsRowFormula",
      ].contains(node.name) ||
      node.text.is_empty() {
      continue
    }
    work.spend(amount=node.text.length() + 1)
    let mut in_table = owner == table.part
    if owner == table.sheet &&
      tree.nodes.get(node.parent) is Some(parent) &&
      parent.name == "c" {
      in_table = parent
        .attribute("r")
        .map(value => table.range.contains(Address::parse(value)))
        .unwrap_or(false)
    }
    if column is Some(_) &&
      owner == table.sheet &&
      !in_table &&
      node.name != "f" &&
      formula_tokens(node.text).any(token => token is Brackets(_)) {
      @failure.reject(
        "protected-content", "Local table references in worksheet rules require table-aware editing",
      )
    }
    let text = table_reference_formula(node.text, table, in_table, name, column)
    if text != node.text {
      result.append(axis_text_change(tree, node, text))
    }
  }
  result
}

///|
fn Session::rename_table(
  self : Session,
  sheet : String,
  id : Int32,
  name : String,
  column~ : Int32? = None,
) -> Json raise @failure.Failure {
  let reason = self.sheet_rename_reason(
    structure=false,
    tables=true,
    pivots=true,
    analysis=true,
    pictures=true,
    charts=true,
  )
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
  guard table.reason.is_empty() && !self.sheets[self.sheet_index(sheet)].locked else {
    @failure.reject("protected-content", "Table or worksheet is protected")
  }
  let column = column.map(id => {
    table.columns
    .search_by(column => column.id == id)
    .unwrap_or_error(
      @failure.Failure(
        code="invalid-operation",
        message="Table column identity does not exist",
        part=table.part,
        offset=-1,
      ),
    )
  })
  if column is Some(column) {
    guard column >= 0 &&
      column < table.columns.length() &&
      table.headers == 1 &&
      !name.is_empty() &&
      name.length() <= 255 &&
      @xml.valid_text(name) &&
      !table.columns.any(item => {
        item.id != table.columns[column].id &&
        item.name.to_upper() == name.to_upper()
      }) else {
      @failure.reject("invalid-name", "Invalid or duplicate table column name")
    }
    if table.columns[column].name == name {
      return self.query()
    }
  } else {
    validate_defined_name(name)
    guard !tables.any(other => {
        other.id != id && other.name.to_upper() == name.to_upper()
      }) &&
      !self.formula_names().sources.keys().any(key => key.1 == name.to_upper()) else {
      @failure.reject("invalid-name", "Table name already exists")
    }
    if table.name == name {
      return self.query()
    }
  }
  let parts = self.parts.copy()
  let work : FormulaWork = {
    remaining: 1048576,
    date1904: self.date1904,
    origin: self.focus,
    names: self.formula_names(),
  }
  let edits : Array[(String, @xml.Edit)] = []
  let sheets = self.sheets.copy()
  let workbook_changes = table_formula_changes(
    self.workbook,
    table,
    name,
    column,
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
    let document = self.part_xml(original.part)
    let changes = table_formula_changes(
      document,
      table,
      name,
      column,
      original.part,
      work,
    )
    if original.id == id {
      let tree = Tree::new(document)
      let root = tree.root("table")
      changes.append(
        if column is Some(column) {
          let node = tree.all(
              tree.one(root.id, "tableColumns").unwrap().id,
              "tableColumn",
            )[column]
          metadata_changes(node, [("name", encoded_text(name))])
        } else {
          metadata_changes(root, [("name", name), ("displayName", name)])
        },
      )
    }
    if !changes.is_empty() {
      let (document, edit) = document.edit_source(changes)
      parts[original.part] = document
      edits.push((original.part, edit))
    }
  }
  for index, original in self.sheets {
    let changes = table_formula_changes(
      original.document,
      table,
      name,
      column,
      original.id,
      work,
    )
    let mut document = original.document
    if !changes.is_empty() {
      let (next, edit) = document.edit_source(changes)
      document = next
      edits.push((original.id, edit))
    }
    if original.id == sheet && column is Some(column) {
      let current = Sheet::read(
        original.id,
        original.name,
        original.state,
        document,
        self.strings,
        self.styles.length(),
      )
      let address = Address::{
        row: table.range.top,
        column: table.range.left + column,
      }
      guard current.cells
        .get(address.name())
        .map(cell => {
          cell.read_only.is_empty() &&
          cell.group is None &&
          cell.formula is None
        })
        .unwrap_or(true) else {
        @failure.reject(
          "protected-content", "Table header source requires editing support",
        )
      }
      let (next, edit) = current.prepare(
        Map([
          (
            address.name(),
            { value: Text(name), formula: None, keep_shared: false, },
          ),
        ]),
      )
      document = next
      edits.push((original.id, edit))
    }
    if document.source() != original.document.source() {
      sheets[index] = Sheet::read(
        original.id,
        original.name,
        original.state,
        document,
        self.strings,
        self.styles.length(),
      )
    }
  }
  let calculation = self.calculate(sheets, None, [], workbook, parts~)
  edits.append(self.cache_edits(sheets, calculation))
  self.commit(sheets, workbook, calculation, edits, self.selection, parts~, table_edits=[
    table.part,
  ])
  self.query()
}
