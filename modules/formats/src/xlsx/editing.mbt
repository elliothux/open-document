///|
fn escaped_attribute(value : String) -> String raise @failure.Failure {
  @xml.escape_text(value).replace_all(old="\"", new="&quot;")
}

///|
fn value_xml(
  prefix : String,
  value : Value,
) -> (String, String) raise @failure.Failure {
  match value {
    Blank => ("", "")
    Number(value) => ("", "<\{prefix}v>\{value}</\{prefix}v>")
    Boolean(value) =>
      (" t=\"b\"", "<\{prefix}v>\{if value { 1 } else { 0 }}</\{prefix}v>")
    Text(text) =>
      (
        " t=\"inlineStr\"",
        "<\{prefix}is><\{prefix}t xml:space=\"preserve\">\{encode_text(text)}</\{prefix}t></\{prefix}is>",
      )
    Error(_) =>
      @failure.reject(
        "invalid-operation", "Error values must come from formulas",
      )
  }
}

///|
fn Sheet::cell_xml(
  self : Sheet,
  tree : Tree,
  address : Address,
  value : CellContent,
) -> String raise @failure.Failure {
  let key = address.name()
  let original = self.cells.get(key).map(cell => tree.nodes[cell.node])
  let qualified = original
    .map(node => node.qualified)
    .unwrap_or(
      tree.nodes[self.data].qualified[:tree.nodes[self.data].qualified.length() -
      9].to_owned() +
      "c",
    )
  let prefix = qualified[:qualified.length() - 1].to_owned()
  let (kind, generated) = content_xml(prefix, value)
  let content = if value.keep_shared &&
    value.formula is Some(formula) &&
    original is Some(node) &&
    tree.one(node.id, "f") is Some(f) {
    generated.replace(
      old="<\{prefix}f>\{@xml.escape_text(formula)}</\{prefix}f>",
      new=self.document.source()[f.start:f.end],
    )
  } else {
    generated
  }
  let output = StringBuilder()
  output <+ "<\{qualified} r=\"\{key}\""
  if original is Some(node) {
    let source = self.document.source()
    for attribute in node.attributes {
      if !(attribute.uri.is_empty() && ["r", "t"].contains(attribute.name)) {
        // Cache updates may touch read-only formulas; retain their other attributes exactly.
        let mut end = attribute.start - 1
        while end > node.start && source[end] != 61 {
          end -= 1
        }
        while end > node.start &&
              [32, 9, 10, 13].contains(source[end - 1].to_int()) {
          end -= 1
        }
        let mut start = end
        while start > node.start &&
              ![32, 9, 10, 13, 60].contains(source[start - 1].to_int()) {
          start -= 1
        }
        output.write_char(' ')
        output.write_view(source[start:attribute.end + 1])
      }
    }
    for (prefix, uri) in node.namespaces {
      output <+
        " \{if prefix.is_empty() { "xmlns" } else { "xmlns:" + prefix }}=\"\{escaped_attribute(uri)}\""
    }
  }
  output.write_string(kind)
  output <+ ">"
  output.write_string(content)
  if original is Some(node) && !node.empty {
    let source = self.document.source()
    let mut cursor = node.opening_end
    for child in tree.children.get(node.id).unwrap_or([]) {
      if child.uri == spreadsheet_uri && ["v", "f", "is"].contains(child.name) {
        output.write_view(source[cursor:child.start])
        cursor = child.end
      }
    }
    output.write_view(source[cursor:node.closing_start])
  }
  output <+ "</\{qualified}>"
  output.to_string()
}

///|
fn insertion(node : @xml.Node, content : String) -> @xml.SourceChange {
  if node.empty {
    {
      node: node.id,
      offset: node.opening_end - node.start - 2,
      length: 2,
      xml: ">\{content}</\{node.qualified}>",
    }
  } else {
    {
      node: node.id,
      offset: node.closing_start - node.start,
      length: 0,
      xml: content,
    }
  }
}

///|
fn Sheet::prepare(
  self : Sheet,
  updates : Map[String, CellContent],
) -> (@xml.Document, @xml.Edit) raise @failure.Failure {
  let tree = Tree::new(self.document)
  let changes : Array[@xml.SourceChange] = []
  let pending : Map[Int, Array[(Address, CellContent)]] = Map([])
  for name, value in updates {
    let address = Address::parse(name)
    if self.cells.get(name) is Some(cell) {
      let node = tree.nodes[cell.node]
      let row = tree.nodes[node.parent]
      changes.push({
        node: row.id,
        offset: node.start - row.start,
        length: node.end - node.start,
        xml: self.cell_xml(tree, address, value),
      })
    } else if value.value != Blank || value.formula is Some(_) {
      if pending.get(address.row) is Some(items) {
        items.push((address, value))
      } else {
        pending[address.row] = [(address, value)]
      }
    }
  }
  // Combine insertions at the same source offset into one XML patch.
  let insertions : Map[(Int, Int), String] = Map([])
  let row_numbers = pending.keys().collect()
  row_numbers.sort()
  for row_number in row_numbers {
    let items = pending[row_number]
    items.sort_by((a, b) => a.0.column.compare(b.0.column))
    if self.rows.get(row_number) is Some(row_id) {
      let row = tree.nodes[row_id]
      for (address, value) in items {
        let next = tree
          .all(row_id, "c")
          .iter()
          .find_first(node => {
            self.cells
            .values()
            .any(cell => {
              cell.node == node.id && cell.address.column > address.column
            })
          })
        let offset = next
          .map(node => node.start - row.start)
          .unwrap_or(
            if row.empty {
              row.opening_end - row.start - 2
            } else {
              row.closing_start - row.start
            },
          )
        let key = (row_id, offset)
        insertions[key] = insertions.get(key).unwrap_or("") +
          self.cell_xml(tree, address, value)
      }
    } else {
      let data = tree.nodes[self.data]
      let prefix = data.qualified[:data.qualified.length() - 9].to_owned()
      let content = items
        .map(item => self.cell_xml(tree, item.0, item.1))
        .join("")
      let row = "<\{prefix}row r=\"\{row_number}\">\{content}</\{prefix}row>"
      let next = tree
        .all(self.data, "row")
        .iter()
        .find_first(node => {
          natural(node.attribute("r").unwrap_or("0"), 1048576) > row_number
        })
      let offset = next
        .map(node => node.start - data.start)
        .unwrap_or(
          if data.empty {
            data.opening_end - data.start - 2
          } else {
            data.closing_start - data.start
          },
        )
      let key = (self.data, offset)
      insertions[key] = insertions.get(key).unwrap_or("") + row
    }
  }
  for (id, offset), content in insertions {
    let node = tree.nodes[id]
    if node.empty {
      changes.push(insertion(node, content))
    } else {
      changes.push({ node: id, offset, length: 0, xml: content, })
    }
  }
  self.document.edit_source(changes)
}

///|
pub fn Session::replace(
  self : Session,
  revision : Int,
  sheet : String,
  range : String,
  values : Array[Array[String]],
  literal~ : Bool = false,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  guard self.revision < 2147483647 else {
    @failure.reject("limit-exceeded", "Workbook revision exhausted")
  }
  guard self.read_only.is_empty() else {
    @failure.reject("protected-content", self.read_only)
  }
  let index = self.sheet_index(sheet)
  let current = self.sheets[index]
  guard !current.locked else {
    @failure.reject("protected-content", "Worksheet is protected")
  }
  let parsed = Range::parse(range)
  let target = if parsed.top == parsed.bottom && parsed.left == parsed.right {
    let merged = current.cell_range({ row: parsed.top, column: parsed.left, })
    {
      top: merged.top,
      bottom: merged.top,
      left: merged.left,
      right: merged.left,
    }
  } else {
    parsed
  }
  let count = (target.bottom - target.top + 1).to_int64() *
    (target.right - target.left + 1).to_int64()
  guard count <= 4096 &&
    values.length() == target.bottom - target.top + 1 &&
    values.all(row => row.length() == target.right - target.left + 1) else {
    @failure.reject(
      "limit-exceeded", "Rectangular edit exceeds 4096 cells or has invalid dimensions",
    )
  }
  let single = count == 1
  guard single || !current.merges.any(merge => merge.intersects(target)) else {
    @failure.reject(
      "protected-content", "Rectangular writes cannot intersect merged cells",
    )
  }
  let updates : Map[String, CellContent] = Map([])
  let mut units = 0
  for row, fields in values {
    for column, text in fields {
      let mut address = { row: target.top + row, column: target.left + column, }
      if single {
        for merge in current.merges {
          if merge.contains(address) {
            address = { row: merge.top, column: merge.left, }
            break
          }
        }
      }
      let key = address.name()
      let cell = current.cells.get(key)
      guard cell.map(cell => cell.read_only.is_empty()).unwrap_or(true) else {
        @failure.reject("protected-content", cell.unwrap().read_only)
      }
      units += text.length()
      guard units <= 1048576 else {
        @failure.reject("limit-exceeded", "Edit input exceeds UTF-16 budget")
      }
      let value = cell_content(text, literal)
      if value.formula is Some(formula) &&
        cell.bind(cell => cell.formula) == Some(formula) {
        continue
      }
      if cell.map(cell => cell.value).unwrap_or(Blank) != value.value ||
        cell.bind(cell => cell.formula) != value.formula {
        updates[key] = value
      }
    }
  }
  if updates.is_empty() {
    return self.query(sheet=Some(sheet), range=Some(target.name()))
  }
  let groups : Map[Int, Bool] = Map([])
  for key in updates.keys() {
    if current.cells.get(key).bind(cell => cell.group) is Some(group) {
      groups[group] = true
    }
  }
  for key, cell in current.cells {
    if cell.group is Some(group) &&
      groups.contains(group) &&
      !updates.contains(key) {
      updates[key] = {
        value: cell.value,
        formula: cell.formula,
        keep_shared: false,
      }
    }
  }
  let (document, edit) = current.prepare(updates)
  let candidate = self.sheets.copy()
  candidate[index] = Sheet::read(
    current.id,
    current.name,
    current.state,
    document,
    self.strings,
    self.style_count,
  )
  let edits : Array[(String, @xml.Edit)] = [(current.id, edit)]
  let changed = updates
    .keys()
    .collect()
    .map(key => {
      let address = Address::parse(key)
      (
        index,
        {
          top: address.row,
          left: address.column,
          bottom: address.row,
          right: address.column,
        },
      )
    })
  let calculation = Calculation::build(candidate, self.calculation, changed)
  for entry in self.cache_edits(candidate, calculation) {
    edits.push(entry)
  }
  self.commit(candidate, self.workbook, calculation, edits, (sheet, target))
  self.query(sheet=Some(sheet), range=Some(target.name()))
}

///|
fn Session::validate(
  self : Session,
  sheets : Array[Sheet],
  workbook? : @xml.Document,
) -> Unit raise @failure.Failure {
  let mut cells = 0
  let mut units = 0
  let replacements : Map[String, Bytes] = Map([])
  let workbook = workbook.unwrap_or(self.workbook)
  if !workbook.is_original() {
    replacements[self.main] = workbook.bytes()
  }
  for sheet in sheets {
    cells += sheet.cells.length()
    for cell in sheet.cells.values() {
      match cell.value {
        Text(text) => units += text.length()
        _ => ()
      }
    }
    if !sheet.document.is_original() {
      replacements[sheet.id] = sheet.document.bytes()
    }
  }
  guard cells <= 100000 && units <= 4194304 else {
    @failure.reject("limit-exceeded", "Workbook cells or text exceed budget")
  }
  self.opc.validate_changes(replacements)
}

///|
pub fn Session::undo(
  self : Session,
  revision : Int,
  redo~ : Bool = false,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let source = if redo { self.redo } else { self.history }
  let target = if redo { self.history } else { self.redo }
  guard source.last() is Some(entry) else { return self.query() }
  guard self.revision < 2147483647 else {
    @failure.reject("limit-exceeded", "Workbook revision exhausted")
  }
  let sheets = self.sheets.copy()
  let mut workbook = self.workbook
  for (part, edit) in (if redo { entry.edits } else { entry.edits.rev() }) {
    if part == self.main {
      workbook = workbook.apply(edit, forward=redo)
      continue
    }
    let index = sheets.search_by(sheet => sheet.id == part).unwrap()
    let sheet = sheets[index]
    let document = sheet.document.apply(edit, forward=redo)
    sheets[index] = Sheet::read(
      sheet.id,
      sheet.name,
      sheet.state,
      document,
      self.strings,
      self.style_count,
    )
  }
  let sheets = self.ordered_sheets(workbook, sheets)
  self.validate(sheets, workbook~)
  let calculation = Calculation::build(sheets, None, [])
  self.workbook = workbook
  self.sheets = sheets
  self.calculation = Some(calculation)
  self.selection = if redo { entry.after } else { entry.before }
  self.anchor = { row: self.selection.1.top, column: self.selection.1.left, }
  self.focus = { row: self.selection.1.bottom, column: self.selection.1.right, }
  self.grid = None
  ignore(source.pop())
  target.push(entry)
  self.revision += 1
  self.query()
}

///|
pub fn Session::save(self : Session) -> Bytes raise @failure.Failure {
  self.check()
  let replacements : Map[String, Bytes] = Map([])
  if !self.workbook.is_original() {
    replacements[self.main] = self.workbook.bytes()
  }
  let mut modified = false
  let mut shared_count = 0
  for sheet in self.sheets {
    if !sheet.document.is_original() {
      replacements[sheet.id] = sheet.document.bytes()
      let original = Tree::new(self.opc.xml(sheet.id))
      let data = original
        .one(original.root("worksheet").id, "sheetData")
        .unwrap()
      let current = sheet.document.node(sheet.data)
      if original.document.source()[data.start:data.end] !=
        sheet.document.source()[current.start:current.end] {
        modified = true
      }
    }
    for cell in sheet.cells.values() {
      if cell.shared is Some(_) {
        shared_count += 1
      }
    }
  }
  if modified && self.strings_part is Some(part) {
    let document = self.opc.xml(part)
    let root = document.nodes()[0]
    replacements[part] = metadata_attributes(document, root, [
      ("count", shared_count.to_string()),
      ("uniqueCount", self.strings.length().to_string()),
    ]).bytes()
  }
  let removed = if modified { self.save_metadata(replacements) } else { [] }
  let output = self.opc.save(replacements, removed~)
  let checked = @opc.Package::open(output, self.budget)
  checked.close()
  output
}
