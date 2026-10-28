///|
fn Session::table_for_edit(
  self : Session,
  sheet : String,
  id : Int32,
  sparklines~ : Bool = false,
  threads~ : Bool = false,
) -> StructuredTable raise @failure.Failure {
  let reason = self.sheet_rename_reason(
    structure=false,
    tables=true,
    pivots=true,
    analysis=true,
    pictures=true,
    charts=true,
    sparklines~,
    threads~,
  )
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  guard self
    .table_definitions(self.sheets, self.workbook, self.parts)
    .iter()
    .find_first(table => table.sheet == sheet && table.id == id)
    is Some(table) else {
    @failure.reject(
      "invalid-operation", "Table is outside the selected worksheet",
    )
  }
  let current = self.sheets[self.sheet_index(sheet)]
  guard table.reason.is_empty() &&
    table.style_reason.is_empty() &&
    !current.locked &&
    current.state == "visible" else {
    @failure.reject("protected-content", "Table or worksheet is protected")
  }
  table
}

///|
fn table_edit_tree(
  table : StructuredTable,
  document : @xml.Document,
) -> Tree raise @failure.Failure {
  let tree = Tree::new(document)
  let root = tree.root("table")
  let columns = tree.one(root.id, "tableColumns").unwrap()
  let filter = tree.one(root.id, "autoFilter")
  guard columns.attributes.all(attribute => {
      attribute.uri.is_empty() && attribute.name == "count"
    }) &&
    tree.children
    .get(columns.id)
    .unwrap_or([])
    .all(node => node.uri == spreadsheet_uri && node.name == "tableColumn") &&
    (tree.one(root.id, "sortState") is None || table.sort is Some(_)) &&
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
      "protected-content",
      "Table filter, sort or column metadata requires editing support",
      part=table.part,
    )
  }
  for node in document.nodes() {
    if ["calculatedColumnFormula", "totalsRowFormula"].contains(node.name) {
      guard node.uri == spreadsheet_uri &&
        node.attributes.all(attribute => {
          attribute.uri.is_empty() && attribute.name == "array"
        }) &&
        !flag(node, "array") &&
        tree.children.get(node.id).unwrap_or([]).is_empty() else {
        @failure.reject(
          "protected-content",
          "Array or extended table formula source requires editing support",
          part=table.part,
        )
      }
    }
  }
  tree
}

///|
fn table_column_node(
  tree : Tree,
  index : Int32,
) -> @xml.Node raise @failure.Failure {
  tree.all(
    tree.one(tree.root("table").id, "tableColumns").unwrap().id,
    "tableColumn",
  )[index]
}

///|
fn table_column_index(
  table : StructuredTable,
  id : Int32,
) -> Int32 raise @failure.Failure {
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
}

///|
fn table_formula_change(
  tree : Tree,
  column : @xml.Node,
  kind : String,
  text : String?,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  match (tree.one(column.id, kind), text) {
    (Some(node), Some(text)) =>
      if text == node.text {
        []
      } else {
        axis_text_change(tree, node, text)
      }
    (Some(node), None) => [sheet_node_removal(tree, node)]
    (None, Some(text)) => {
      let markup = "<od:\{kind} xmlns:od=\"\{spreadsheet_uri}\">\{@xml.escape_text(text)}</od:\{kind}>"
      if kind == "calculatedColumnFormula" &&
        tree.one(column.id, "totalsRowFormula") is Some(next) {
        [
          {
            node: column.id,
            offset: next.start - column.start,
            length: 0,
            xml: markup,
          },
        ]
      } else {
        [insertion(column, markup)]
      }
    }
    (None, None) => []
  }
}

///|
fn same_table_formula(
  first : String?,
  second : String,
) -> Bool raise @failure.Failure {
  first.map(text => parse_formula(text).source() == second).unwrap_or(false) catch {
    @failure.Failure(code="limit-exceeded", ..) as error => raise error
    _ => false
  }
}

///|
fn table_attribute_removals(
  document : @xml.Document,
  node : @xml.Node,
  names : Array[String],
) -> Array[@xml.SourceChange] {
  let source = document.source()
  let changes : Array[@xml.SourceChange] = []
  for attribute in node.attributes {
    if !attribute.uri.is_empty() || !names.contains(attribute.name) {
      continue
    }
    let mut end = attribute.start - 1
    while end > node.start && source[end] != 61 {
      end -= 1
    }
    while end > node.start && [32, 9, 10, 13].contains(source[end - 1].to_int()) {
      end -= 1
    }
    let mut start = end
    while start > node.start &&
          ![32, 9, 10, 13, 60].contains(source[start - 1].to_int()) {
      start -= 1
    }
    changes.push({
      node: node.id,
      offset: start - node.start,
      length: attribute.end + 1 - start,
      xml: "",
    })
  }
  changes
}

///|
fn Session::finish_table_edit(
  self : Session,
  table : StructuredTable,
  parts : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
  updates : Map[String, CellContent],
) -> Json raise @failure.Failure {
  if edits.is_empty() && updates.is_empty() {
    return self.query()
  }
  let index = self.sheet_index(table.sheet)
  let current = self.sheets[index]
  let sheets = self.sheets.copy()
  if !updates.is_empty() {
    for name in updates.keys() {
      guard current.cells
        .get(name)
        .map(cell => cell.read_only.is_empty() && cell.group is None)
        .unwrap_or(true) else {
        @failure.reject(
          "protected-content", "Table authoring crosses protected cell source",
        )
      }
    }
    let (document, edit) = current.prepare(updates)
    sheets[index] = Sheet::read(
      current.id,
      current.name,
      current.state,
      document,
      self.strings,
      self.styles.length(),
    )
    edits.push((table.sheet, edit))
  }
  let calculation = self.calculate(sheets, None, [], self.workbook, parts~)
  self.validate_inputs(
    sheets,
    calculation,
    Map([(index, updates.keys().to_array())]),
    false,
  )
  edits.append(self.cache_edits(sheets, calculation))
  self.commit(
    sheets,
    self.workbook,
    calculation,
    edits,
    self.selection,
    parts~,
    table_edits=[table.part],
  )
  self.query()
}
