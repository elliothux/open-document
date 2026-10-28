///|
pub(all) enum TableTotal {
  Clear
  Label(String)
  Formula(String)
  Aggregate(String)
}

///|
fn table_total_code(kind : String) -> Int32 raise @failure.Failure {
  match kind {
    "average" => 101
    "countNums" => 102
    "count" => 103
    "max" => 104
    "min" => 105
    "stdDev" => 107
    "sum" => 109
    "var" => 110
    _ =>
      @failure.reject("invalid-operation", "Unsupported table total function")
  }
}

///|
fn table_total_content(
  table : StructuredTable,
  position : Int32,
) -> CellContent raise @failure.Failure {
  let column = table.columns[position]
  let formula = if column.total_formula is Some(formula) {
    Some(formula)
  } else if column.total_function is Some(kind) && kind != "none" {
    let code = table_total_code(kind)
    Some("SUBTOTAL(\{code},\{table.name}[\{structured_escape(column.name)}])")
  } else {
    None
  }
  {
    value: if formula is Some(_) {
      Blank
    } else {
      column.total_label.map(text => Text(text)).unwrap_or(Blank)
    },
    formula,
    keep_shared: false,
  }
}

///|
fn Session::write_table_total(
  self : Session,
  table : StructuredTable,
  position : Int32,
  setting : TableTotal,
  parts : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
) -> Unit raise @failure.Failure {
  let source = parts
    .get(table.part)
    .unwrap_or_else(() => self.part_xml(table.part))
  guard (edits.length() + 1).to_int64() * source.source().length().to_int64() <=
    1048576 else {
    @failure.reject(
      "limit-exceeded", "Table total metadata editing exceeds work budget",
    )
  }
  let tree = table_edit_tree(table, source)
  let node = table_column_node(tree, position)
  let attributes : Array[(String, String)] = []
  let removed : Array[String] = []
  let formula = match setting {
    Clear => {
      attributes.push(("totalsRowFunction", "none"))
      removed.push("totalsRowLabel")
      None
    }
    Label(text) => {
      guard text.length() <= 32767 && @xml.valid_text(text) else {
        @failure.reject(
          "limit-exceeded", "Table total label exceeds text budget",
        )
      }
      attributes.push(("totalsRowLabel", encoded_text(text)))
      removed.push("totalsRowFunction")
      None
    }
    Aggregate(kind) => {
      ignore(table_total_code(kind))
      attributes.push(("totalsRowFunction", kind))
      removed.push("totalsRowLabel")
      None
    }
    Formula(text) => {
      let text = text.trim().to_owned()
      let text = text.strip_prefix("=").unwrap_or(text[:]).to_owned()
      guard !text.is_empty() && text.length() <= 8192 && @xml.valid_text(text) else {
        @failure.reject(
          "limit-exceeded", "Table total formula must contain 1..8192 UTF-16 units",
        )
      }
      let expression = parse_formula(text)
      attributes.push(("totalsRowFunction", "custom"))
      removed.push("totalsRowLabel")
      let old = tree.one(node.id, "totalsRowFormula").map(node => node.text)
      Some(
        if same_table_formula(old, expression.source()) {
          old.unwrap()
        } else {
          text
        },
      )
    }
  }
  let changes = metadata_changes(node, attributes)
  changes.append(table_attribute_removals(source, node, removed))
  let source = if changes.is_empty() {
    source
  } else {
    let (document, edit) = source.edit_source(changes)
    edits.push((table.part, edit))
    parts[table.part] = document
    document
  }
  let tree = Tree::new(source)
  let changes = table_formula_change(
    tree,
    table_column_node(tree, position),
    "totalsRowFormula",
    formula,
  )
  if !changes.is_empty() {
    let (document, edit) = source.edit_source(changes)
    parts[table.part] = document
    edits.push((table.part, edit))
  }
}

///|
fn same_table_content(
  cell : Cell?,
  content : CellContent,
) -> Bool raise @failure.Failure {
  if content.formula is Some(formula) {
    same_table_formula(
      cell.bind(cell => cell.formula),
      parse_formula(formula).source(),
    )
  } else {
    cell.bind(cell => cell.formula) is None &&
    cell.map(cell => cell.value).unwrap_or(Blank) == content.value
  }
}

///|
fn Session::set_table_total(
  self : Session,
  sheet : String,
  id : Int32,
  column : Int32,
  setting : TableTotal,
) -> Json raise @failure.Failure {
  let table = self.table_for_edit(sheet, id)
  guard table.totals == 1 else {
    @failure.reject(
      "invalid-operation", "Show the totals row before setting a column total",
    )
  }
  let position = table_column_index(table, column)
  let parts = self.parts.copy()
  let edits : Array[(String, @xml.Edit)] = []
  self.write_table_total(table, position, setting, parts, edits)
  let current = self.sheets[self.sheet_index(sheet)]
  let candidate = read_table(
    current,
    table.part,
    parts.get(table.part).unwrap_or_else(() => self.part_xml(table.part)),
  )
  let content = table_total_content(candidate, position)
  let address = Address::{
    row: table.range.bottom,
    column: table.range.left + position,
  }.name()
  let updates : Map[String, CellContent] = Map([])
  if !same_table_content(current.cells.get(address), content) {
    updates[address] = content
  }
  self.finish_table_edit(table, parts, edits, updates)
}
