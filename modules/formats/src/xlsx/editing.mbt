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
    Error(value) =>
      (" t=\"e\"", "<\{prefix}v>\{@xml.escape_text(value)}</\{prefix}v>")
  }
}

///|
fn Sheet::cell_xml(
  self : Sheet,
  tree : Tree,
  address : Address,
  value : CellContent,
  style~ : Int? = None,
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
  if style is Some(id) {
    output <+ " s=\"\{id}\""
  }
  if original is Some(node) {
    let source = self.document.source()
    for attribute in node.attributes {
      if !(attribute.uri.is_empty() &&
        (
          ["r", "t"].contains(attribute.name) ||
          (style is Some(_) && attribute.name == "s")
        )) {
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
  styles~ : Map[String, Int] = Map([]),
  preserve_values~ : Bool = false,
  fragments~ : Map[String, String] = Map([]),
) -> (@xml.Document, @xml.Edit) raise @failure.Failure {
  let tree = Tree::new(self.document)
  fn markup(
    address : Address,
    value : CellContent,
  ) -> String raise @failure.Failure {
    let name = address.name()
    fragments
    .get(name)
    .unwrap_or_else(() => {
      self.cell_xml(tree, address, value, style=styles.get(name))
    })
  }
  let changes : Array[@xml.SourceChange] = []
  let pending : Map[Int, Array[(Address, CellContent)]] = Map([])
  for name, value in updates {
    let address = Address::parse(name)
    if self.cells.get(name) is Some(cell) {
      let node = tree.nodes[cell.node]
      if preserve_values && styles.get(name) is Some(style) {
        changes.append(metadata_changes(node, [("s", style.to_string())]))
        continue
      }
      let row = tree.nodes[node.parent]
      changes.push({
        node: row.id,
        offset: node.start - row.start,
        length: node.end - node.start,
        xml: markup(address, value),
      })
    } else if value.value != Blank ||
      value.formula is Some(_) ||
      styles.contains(name) {
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
          markup(address, value)
      }
    } else {
      let data = tree.nodes[self.data]
      let prefix = data.qualified[:data.qualified.length() - 9].to_owned()
      let content = items.map(item => markup(item.0, item.1)).join("")
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
  accept_warnings~ : Bool = false,
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
      let reason = self.cell_edit_reason(current, address)
      guard reason.is_empty() else {
        @failure.reject("protected-content", reason)
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
  self.commit_cells(Map([(index, updates)]), (sheet, target), accept_warnings~)
}

///|
fn Session::validate(
  self : Session,
  sheets : Array[Sheet],
  workbook? : @xml.Document,
  parts? : Map[String, @xml.Document],
  removed~ : Array[String] = self.removed,
) -> Unit raise @failure.Failure {
  let mut cells = 0
  let mut units = 0
  let workbook = workbook.unwrap_or(self.workbook)
  let replacements = self.replacements(
    sheets,
    workbook,
    parts.unwrap_or(self.parts),
  )
  for sheet in sheets {
    cells += sheet.cells.length()
    for cell in sheet.cells.values() {
      match cell.value {
        Text(text) => units += text.length()
        _ => ()
      }
    }
  }
  guard cells <= 100000 && units <= 4194304 else {
    @failure.reject("limit-exceeded", "Workbook cells or text exceed budget")
  }
  self.opc.validate_changes(replacements, removed~)
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
  let parts = self.parts.copy()
  let removed_parts = self.removed.copy()
  let deleted_documents : Map[String, @xml.Document] = Map([])
  let mut deleted_sheet : Sheet? = None
  let mut removed : Sheet? = None
  let removed_created_parts : Map[String, @xml.Document] = Map([])
  let documents : Map[String, @xml.Document] = Map([])
  if redo && entry.created is Some(sheet) {
    sheets.push(sheet)
  }
  if redo {
    for name, document in entry.created_parts {
      guard !parts.contains(name) else {
        @failure.reject(
          "invalid-operation", "Created worksheet part already exists",
        )
      }
      parts[name] = document
    }
  }
  if !redo {
    if entry.deleted is Some(sheet) {
      sheets.push(sheet)
    }
    for name, document in entry.removed {
      if entry.deleted.map(sheet => sheet.id) != Some(name) {
        parts[name] = document
      }
      if removed_parts.search(name) is Some(index) {
        ignore(removed_parts.remove(index))
      }
    }
  }
  for (part, edit) in (if redo { entry.edits } else { entry.edits.rev() }) {
    if part == self.main {
      workbook = workbook.apply(edit, forward=redo)
      continue
    }
    guard sheets.search_by(sheet => sheet.id == part) is Some(index) else {
      let document = parts.get(part).unwrap_or_else(() => self.opc.xml(part))
      parts[part] = document.apply(edit, forward=redo)
      continue
    }
    let sheet = sheets[index]
    let document = documents.get(part).unwrap_or(sheet.document)
    documents[part] = document.apply(edit, forward=redo)
  }
  if !redo && entry.created is Some(created) {
    let sheet = sheets.remove(
      sheets.search_by(sheet => sheet.id == created.id).unwrap(),
    )
    let sheet = {
      ..sheet,
      document: documents.get(sheet.id).unwrap_or(sheet.document),
    }
    guard sheet.document.source() == created.document.source() else {
      @failure.reject(
        "invalid-operation", "Created worksheet history has changed",
      )
    }
    removed = Some(sheet)
  }
  if !redo {
    for name, snapshot in entry.created_parts {
      guard parts.get(name) is Some(current) &&
        current.source() == snapshot.source() else {
        @failure.reject(
          "invalid-operation", "Created worksheet part history has changed",
        )
      }
      removed_created_parts[name] = current
      parts.remove(name)
    }
  }
  if redo && entry.deleted is Some(deleted) {
    let sheet = sheets.remove(
      sheets.search_by(sheet => sheet.id == deleted.id).unwrap(),
    )
    deleted_sheet = Some(sheet)
  }
  if redo {
    for name, _ in entry.removed {
      deleted_documents[name] = if deleted_sheet is Some(sheet) &&
        name == sheet.id {
        sheet.document
      } else {
        parts.get(name).unwrap_or_else(() => self.opc.xml(name))
      }
      parts.remove(name)
      if self.opc.names.contains(name.to_lower()) {
        removed_parts.push(name)
      }
    }
  }
  let styles = self.styles_from_parts(parts)
  for index, sheet in sheets {
    if documents.get(sheet.id) is Some(document) {
      sheets[index] = Sheet::read(
        sheet.id,
        sheet.name,
        sheet.state,
        document,
        self.strings,
        styles.length(),
      )
    }
  }
  let sheets = self.ordered_sheets(
    workbook,
    sheets,
    parts,
    removed=removed_parts,
  )
  self.validate(sheets, workbook~, parts~, removed=removed_parts)
  guard sheets.all(sheet => {
    sheet.cells.values().all(cell => cell.style < styles.length())
  }) else {
    @failure.reject("malformed-xlsx", "Cell style is outside restored styles")
  }
  let calculation = self.calculate(
    sheets,
    None,
    [],
    workbook,
    parts~,
    removed=removed_parts,
  )
  // Retain XML identity allocation from later undone edits for their next redo.
  if removed is Some(_) {
    entry.created = removed
  }
  for name, document in removed_created_parts {
    entry.created_parts[name] = document
  }
  if deleted_sheet is Some(_) {
    entry.deleted = deleted_sheet
  }
  for name, document in deleted_documents {
    entry.removed[name] = document
  }
  self.workbook = workbook
  self.parts = parts
  self.removed = removed_parts
  self.sheets = sheets
  self.styles = styles
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
  let replacements = self.replacements(self.sheets, self.workbook, self.parts)
  let mut modified = !self.removed.is_empty()
  let mut shared_count = 0
  for sheet in self.sheets {
    if !self.opc.names.contains(sheet.id.to_lower()) {
      modified = modified || !sheet.cells.is_empty()
    } else if !sheet.document.is_original() {
      let original = Tree::new(self.opc.xml(sheet.id))
      let data = original
        .one(original.root("worksheet").id, "sheetData")
        .unwrap()
      if cell_sources(original, data.id) !=
        cell_sources(Tree::new(sheet.document), sheet.data) {
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
  let removed = [
    ..self.removed,
    ..if modified {
      self.save_metadata(replacements)
    } else {
      []
    },
  ]
  let output = self.opc.save(replacements, removed~)
  let checked = @opc.Package::open(output, self.budget)
  checked.close()
  output
}

///|
fn cell_sources(
  tree : Tree,
  data : Int,
) -> Array[String] raise @failure.Failure {
  let cells : Array[String] = []
  let mut previous_row = 0
  for row in tree.all(data, "row") {
    let row_number = natural(
      row.attribute("r").unwrap_or((previous_row + 1).to_string()),
      1048576,
    )
    previous_row = row_number
    let mut previous_column = 0
    for cell in tree.all(row.id, "c") {
      let address = cell
        .attribute("r")
        .map(Address::parse)
        .unwrap_or({ row: row_number, column: previous_column + 1, })
      previous_column = address.column
      let content = tree.children
        .get(cell.id)
        .unwrap_or([])
        .filter(child => {
          child.uri == spreadsheet_uri && ["v", "f", "is"].contains(child.name)
        })
      if !content.is_empty() {
        cells.push(
          address.name() +
          "\n" +
          cell.attribute("t").unwrap_or("n") +
          "\n" +
          content
          .map(node => tree.document.source()[node.start:node.end].to_owned())
          .join(""),
        )
      }
    }
  }
  cells
}
