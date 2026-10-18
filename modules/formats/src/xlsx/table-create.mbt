///|
fn Session::create_table(
  self : Session,
  sheet : String,
  range : String,
  name : String,
) -> Json raise @failure.Failure {
  let reason = self.sheet_rename_reason(structure=false, tables=true)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  validate_defined_name(name)
  let index = self.sheet_index(sheet)
  let current = self.sheets[index]
  let range = Range::parse(range)
  let tables = self.table_definitions(self.sheets, self.workbook, self.parts)
  guard !current.locked && current.state == "visible" else {
    @failure.reject(
      "protected-content", "Select a visible unprotected worksheet",
    )
  }
  guard range.bottom > range.top &&
    !current.merges.any(merge => merge.intersects(range)) &&
    !tables.any(table => table.sheet == sheet && table.range.intersects(range)) &&
    !read_filter(current)
    .map(filter => filter.bounds.intersects(range))
    .unwrap_or(false) else {
    @failure.reject(
      "invalid-operation", "Tables require a header and data row without overlapping tables, merges or filters",
    )
  }
  guard !tables.any(table => table.name.to_upper() == name.to_upper()) &&
    !self.formula_names().sources.keys().any(key => key.1 == name.to_upper()) else {
    @failure.reject("invalid-name", "Table name already exists")
  }
  let width = range.right - range.left + 1
  guard tables.length() < 256 &&
    width +
    tables.iter().fold(init=0, (sum, table) => sum + table.columns.length()) <=
    4096 else {
    @failure.reject(
      "limit-exceeded", "Workbook table or column count exceeds budget",
    )
  }
  let labels : Array[String] = []
  for column in range.left..<=range.right {
    let address = Address::{ row: range.top, column, }.name()
    let cell = current.cells.get(address)
    guard cell
      .map(cell => cell.read_only.is_empty() && cell.group is None)
      .unwrap_or(true) else {
      @failure.reject(
        "protected-content", "Table header source requires editing support",
      )
    }
    let value = self.calculation
      .bind(calculation => calculation.values.get((index, address)))
      .unwrap_or(cell.map(cell => cell.value).unwrap_or(Blank))
    let label = formatted(
      value,
      self.styles[cell.map(cell => cell.style).unwrap_or(0)].format,
      self.date1904,
    )
    guard label.length() <= 255 && @xml.valid_text(label) else {
      @failure.reject("limit-exceeded", "Table header exceeds 255 UTF-16 units")
    }
    labels.push(label)
  }
  let labels = table_header_names(labels, [], name.length())
  let updates : Map[String, CellContent] = Map([])
  let columns = StringBuilder()
  for offset, label in labels {
    let address = Address::{ row: range.top, column: range.left + offset, }.name()
    let cell = current.cells.get(address)
    if cell
      .map(cell => cell.value != Text(label) || cell.formula is Some(_))
      .unwrap_or(true) {
      updates[address] = {
        value: Text(label),
        formula: None,
        keep_shared: false,
      }
    }
    columns <+
      "<tableColumn id=\"\{offset + 1}\" name=\"\{escaped_attribute(encoded_text(label))}\"/>"
  }
  let id = for id in 1..<=257 {
    if !tables.any(table => table.id == id) {
      break id
    }
  } nobreak {
    @failure.reject("limit-exceeded", "Table identities exhausted")
  }
  let plan = self.prepare_cells(Map([(index, updates)]))
  let sheets = plan.sheets
  let edits = plan.edits
  let parts = self.parts.copy()
  let created : Map[String, @xml.Document] = Map([])
  let markup = "<table xmlns=\"\{spreadsheet_uri}\" id=\"\{id}\" name=\"\{escaped_attribute(name)}\" displayName=\"\{escaped_attribute(name)}\" ref=\"\{range.name()}\" headerRowCount=\"1\" totalsRowCount=\"0\" totalsRowShown=\"0\"><autoFilter ref=\"\{range.name()}\"/><tableColumns count=\"\{width}\">\{columns.to_string()}</tableColumns><tableStyleInfo name=\"TableStyleMedium2\" showFirstColumn=\"0\" showLastColumn=\"0\" showRowStripes=\"1\" showColumnStripes=\"0\"/></table>"
  let (_, relation) = self.create_sheet_resource(
    sheet, "table", markup, parts, created, edits,
  )
  let document = sheets[index].document
  let tree = Tree::new(document)
  let root = tree.root("worksheet")
  let reference = "<od:tablePart xmlns:od=\"\{spreadsheet_uri}\" xmlns:r=\"\{relationship_uri[:relationship_uri.length() - 1]}\" r:id=\"\{relation}\"/>"
  let change = if tree.one(root.id, "tableParts") is Some(parent) {
    insertion(parent, reference)
  } else {
    let markup = "<od:tableParts xmlns:od=\"\{spreadsheet_uri}\" count=\"0\">\{reference}</od:tableParts>"
    if tree.children
      .get(root.id)
      .unwrap_or([])
      .iter()
      .find_first(node => node.name == "extLst")
      is Some(node) {
      {
        node: root.id,
        offset: node.start - root.start,
        length: 0,
        xml: markup,
      }
    } else {
      insertion(root, markup)
    }
  }
  let (document, edit) = document.edit_source([change])
  edits.push((sheet, edit))
  let tree = Tree::new(document)
  let parent = tree.one(tree.root("worksheet").id, "tableParts").unwrap()
  let (document, edit) = document.edit_source(
    metadata_changes(parent, [
      ("count", tree.all(parent.id, "tablePart").length().to_string()),
    ]),
  )
  edits.push((sheet, edit))
  sheets[index] = Sheet::read(
    sheet,
    current.name,
    current.state,
    document,
    self.strings,
    self.styles.length(),
  )
  let calculation = self.calculate(sheets, None, [], self.workbook, parts~)
  edits.append(self.cache_edits(sheets, calculation))
  self.commit(
    sheets,
    self.workbook,
    calculation,
    edits,
    (sheet, range),
    parts~,
    created_parts=created,
  )
  self.query()
}
