///|
pub(all) enum TableEdit {
  RowBefore
  RowAfter
  DeleteRow
  ColumnBefore
  ColumnAfter
  DeleteColumn
  MergeCells(Int, Int)
  UnmergeCell
  SplitTable
  AutoFit(String)
  TableWidth(Double)
  ColumnWidth(Int, Double)
  RowHeight(Double, String)
  CellFill(String?)
  CellVerticalAlign(String?)
  CellMargins(@layout.CellMargins?)
  TableMargins(@layout.CellMargins?)
  TableAlign(String)
  HeaderRows(Int)
  TableBorders(Map[String, @layout.BorderStyle?])
  CellBorders(Map[String, @layout.BorderStyle?])
}

///|
priv struct TableChanges {
  items : Array[@xml.SourceChange]
  mut bytes : Int
  limit : Int
}

///|
fn TableChanges::push(
  self : TableChanges,
  change : @xml.SourceChange,
) -> Unit raise @failure.Failure {
  guard change.xml.length() <= self.limit - self.bytes else {
    @failure.reject("limit-exceeded", "Table source exceeds history budget")
  }
  self.bytes += change.xml.length()
  self.items.push(change)
}

///|
fn WordTree::table_children(
  self : WordTree,
  parent : Int,
  name : String,
) -> Array[Int] {
  self.children[parent].filter(id => {
    self.nodes[id].uri == word_uri && self.nodes[id].name == name
  })
}

///|
fn table_position(paragraph : Int) -> Position {
  {
    paragraph,
    offset: 0,
    affinity: "after",
    bidiLevel: None,
    frameStart: None,
  }
}

///|
fn WordTree::table_cell_properties(
  self : WordTree,
  document : @xml.Document,
  cell : Int,
  width : Int,
) -> String raise @failure.Failure {
  let fields = ["<od:tcW od:type=\"dxa\" od:w=\"\{width}\"/>"]
  if self.child(cell, "tcPr") is Some(props) {
    let node = self.nodes[props]
    let source = document.source()[node.start:node.end]
    guard node.attributes.is_empty() &&
      node.text.trim().is_empty() &&
      !source.contains("<!--") &&
      !source.contains("<?") else {
      @failure.reject("protected-content", "Unknown cell property markup")
    }
    for id in self.children[props] {
      if !["tcW", "gridSpan", "vMerge"].contains(self.nodes[id].name) {
        fields.push(self.standalone_markup(document, id))
      }
    }
  }
  "<od:tcPr xmlns:od=\"\{word_uri}\">\{fields.join("")}</od:tcPr>"
}

///|
fn Session::empty_table_cell(
  self : Session,
  tree : WordTree,
  cell : Int,
  width : Int,
) -> String raise @failure.Failure {
  let p = tree.child(cell, "p").unwrap()
  tree.check_editable_paragraph(p, part=self.main)
  tree.check_structure_paragraph(p)
  let original = self.document()
  let paragraph = formatted_properties(
    tree,
    original,
    p,
    "pPr",
    ParagraphFormat::new(pageBreakBefore=Set(false)).properties(),
  )
  let run = tree
    .child(p, "r")
    .bind(id => tree.child(id, "rPr"))
    .map(id => tree.standalone_markup(original, id))
    .unwrap_or(tree.empty_run_properties(original, p))
  let bindings = tree.namespace_bindings(p)
  bindings["od"] = word_uri
  let out = StringBuilder()
  out.write_string("<od:tc")
  for prefix, uri in bindings {
    let name = if prefix.is_empty() { "xmlns" } else { "xmlns:" + prefix }
    out.write_string(" \{name}=\"\{property_attribute(uri)}\"")
  }
  let properties = tree.table_cell_properties(self.document(), cell, width)
  out.write_string(
    ">\{properties}<od:p>\{paragraph}<od:r>\{run}<od:t/></od:r></od:p></od:tc>",
  )
  out.to_string()
}

///|
fn table_remove(tree : WordTree, id : Int) -> @xml.SourceChange {
  let node = tree.nodes[id]
  {
    node: node.parent,
    offset: node.start - tree.nodes[node.parent].start,
    length: node.end - node.start,
    xml: "",
  }
}

///|
/// Edits one row or column at a supported cell range in a single source history.
pub fn Session::edit_table(
  self : Session,
  revision : Int,
  selection : Selection,
  change : TableEdit,
  probe? : @layout.TextProbe,
  profile~ : Map[String, String] = Map([]),
  images? : @layout.Images,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  match change {
    AutoFit(mode) =>
      return self.fit_table(revision, selection, mode, probe, profile, images)
    TableBorders(value) | CellBorders(value) =>
      return self.set_table_borders(
        revision,
        selection,
        value,
        whole_table=change is TableBorders(_),
      )
    HeaderRows(count) =>
      return self.change_table_property(
        revision,
        selection,
        "tblHeader",
        None,
        header_rows=Some(count),
      )
    MergeCells(rows, columns) =>
      return self.merge_table_cells(revision, selection, rows, columns)
    UnmergeCell => return self.unmerge_table_cell(revision, selection)
    SplitTable => return self.split_table(revision, selection)
    TableWidth(value) =>
      return self.size_table(
        revision,
        selection,
        value,
        width=true,
        probe?,
        profile~,
      )
    ColumnWidth(column, value) =>
      return self.size_table(
        revision,
        selection,
        value,
        width=true,
        column=Some(column),
        probe?,
        profile~,
      )
    RowHeight(value, rule) =>
      return self.size_table(revision, selection, value, width=false, rule~)
    CellFill(color) => return self.fill_table_cell(revision, selection, color)
    CellMargins(value) =>
      return self.set_table_margins(revision, selection, value)
    TableMargins(value) =>
      return self.set_table_margins(
        revision,
        selection,
        value,
        whole_table=true,
      )
    TableAlign(value) => {
      guard ["left", "center", "right"].contains(value) else {
        @failure.reject("invalid-operation", "Invalid table alignment")
      }
      return self.change_table_property(
        revision,
        selection,
        "jc",
        Some(Map([("val", Some(value))])),
        whole_table=true,
      )
    }
    CellVerticalAlign(value) => {
      if value is Some(align) && !["top", "center", "bottom"].contains(align) {
        @failure.reject("invalid-operation", "Invalid cell vertical alignment")
      }
      return self.change_table_property(
        revision,
        selection,
        "vAlign",
        value.map(align => Map([("val", Some(align))])),
      )
    }
    _ => ()
  }
  let original = self.document()
  let tree = WordTree::new(original)
  let range = self.paragraph_range(tree, selection, structural=true)
  let cell = tree.nodes[range.start.paragraph].parent
  guard tree.nodes[cell].name == "tc" else {
    @failure.reject(
      "invalid-operation", "Table commands require a cell selection",
    )
  }
  let row = tree.nodes[cell].parent
  let table = tree.nodes[row].parent
  let body = tree.nodes[table].parent
  ignore(self.editable_page_section(tree))
  let flow = self.flow_from(original)
  let model = flow.tables.iter().find_first(t => t.id == table).unwrap()
  guard model.columnSpans.all(row => row.all(span => span == 1)) &&
    model.rowSpans.all(row => row.all(span => span == 1)) else {
    @failure.reject(
      "protected-content", "Merged table rows and columns require grid structure editing",
    )
  }
  let rows = tree.table_children(table, "tr")
  let cells = rows.map(row => tree.table_children(row, "tc"))
  let r = rows.search(row).unwrap()
  let c = cells[r].search(cell).unwrap()
  let row_edit = match change {
    RowBefore | RowAfter | DeleteRow => true
    _ => false
  }
  let removing = match change {
    DeleteRow | DeleteColumn => true
    _ => false
  }
  let before = match change {
    RowBefore | ColumnBefore => true
    _ => false
  }
  let whole = removing &&
    (if row_edit { rows.length() == 1 } else { cells[0].length() == 1 })
  let row_count = rows.length() +
    (if row_edit { if removing { -1 } else { 1 } } else { 0 })
  let column_count = cells[0].length() +
    (if row_edit { 0 } else if removing { -1 } else { 1 })
  guard row_count <= 1000 &&
    column_count <= 63 &&
    row_count.to_int64() * column_count.to_int64() <= 4096L else {
    @failure.reject(
      "limit-exceeded", "Table exceeds row, column or cell budget",
    )
  }
  // Structural extensions and anchors need their own identity/remapping rules.
  for id in [table, ..rows, ..cells.flatten()] {
    let allowed = match tree.nodes[id].name {
      "tbl" => ["tblPr", "tblGrid", "tr"]
      "tr" => ["trPr", "tc"]
      _ => ["tcPr", "p"]
    }
    guard tree.nodes[id].attributes
      .iter()
      .all(a => {
        a.uri == word_uri &&
        ["rsidR", "rsidRPr", "rsidDel", "rsidTr"].contains(a.name)
      }) &&
      tree.children[id]
      .iter()
      .all(child => {
        tree.nodes[child].uri == word_uri &&
        allowed.contains(tree.nodes[child].name)
      }) else {
      @failure.reject(
        "protected-content", "Unknown table structure prevents row or column edits",
      )
    }
    for name in ["tblPr", "tblGrid", "trPr", "tcPr"] {
      guard tree.table_children(id, name).length() <= 1 else {
        @failure.reject("protected-content", "Duplicate table properties")
      }
    }
  }
  let grid = tree.child(table, "tblGrid").unwrap()
  if !row_edit {
    let node = tree.nodes[grid]
    let source = original.source()[node.start:node.end]
    guard node.text.trim().is_empty() &&
      !source.contains("<!--") &&
      !source.contains("<?") else {
      @failure.reject("protected-content", "Unknown table grid markup")
    }
  }
  for id in [grid, ..tree.children[grid]] {
    let node = tree.nodes[id]
    guard node.uri == word_uri &&
      (id == grid || (node.name == "gridCol" && tree.children[id].is_empty())) &&
      node.attributes
      .iter()
      .all(a => id != grid && a.uri == word_uri && a.name == "w") else {
      @failure.reject("protected-content", "Unknown table grid properties")
    }
  }
  for cell in cells.flatten() {
    if tree.child(cell, "tcPr") is Some(props) {
      guard tree.table_children(props, "tcW").length() <= 1 else {
        @failure.reject("protected-content", "Duplicate cell width")
      }
      if tree.child(props, "tcW") is Some(width) {
        guard tree.children[width].is_empty() &&
          tree.nodes[width].attributes
          .iter()
          .all(a => a.uri == word_uri && ["type", "w"].contains(a.name)) else {
          @failure.reject("protected-content", "Unknown cell width properties")
        }
      }
    }
  }
  let limit = self.opc.budget.entry_bytes.min(history_byte_limit / 2)
  let changes : TableChanges = { items: [], bytes: 0, limit, }
  let first = model.rows[0][0][0]
  let affected = model.rows.flatten().flatten().map(p => p.id)
  let removed = if whole {
    cells.flatten()
  } else if removing {
    if row_edit {
      cells[r]
    } else {
      cells.map(row => row[c])
    }
  } else {
    []
  }
  for cell in removed {
    for p in tree.table_children(cell, "p") {
      tree.check_editable_paragraph(p, part=self.main)
      tree.check_structure_paragraph(p)
    }
  }
  let mut target = -1
  if whole {
    changes.push(table_remove(tree, table))
    let siblings = tree.children[body]
    let index = siblings.search(table).unwrap()
    let next = siblings.get(index + 1).filter(id => tree.nodes[id].name == "p")
    if next is Some(p) {
      target = p
    } else {
      let node = tree.nodes[table]
      changes.push({
        node: body,
        offset: node.end - tree.nodes[body].start,
        length: 0,
        xml: "<od:p xmlns:od=\"\{word_uri}\"/>",
      })
    }
  } else if row_edit {
    if removing {
      changes.push(table_remove(tree, row))
      target = model.rows[(r + 1).min(rows.length() - 1)][0][0].id
      if r == rows.length() - 1 {
        target = model.rows[r - 1][0][0].id
      }
    } else {
      let properties = tree
        .child(row, "trPr")
        .map(id => tree.standalone_markup(original, id))
        .unwrap_or("")
      let markup = StringBuilder()
      markup.write_string("<od:tr xmlns:od=\"\{word_uri}\">\{properties}")
      let mut length = markup.to_string().length() + "</od:tr>".length()
      for col, cell in cells[r] {
        let content = self.empty_table_cell(
          tree,
          cell,
          (model.widths[col] * 20).round().to_int(),
        )
        guard content.length() <= limit - length else {
          @failure.reject(
            "limit-exceeded", "Table source exceeds history budget",
          )
        }
        length += content.length()
        markup.write_string(content)
      }
      markup.write_string("</od:tr>")
      let node = tree.nodes[row]
      changes.push({
        node: table,
        offset: (if before { node.start } else { node.end }) -
        tree.nodes[table].start,
        length: 0,
        xml: markup.to_string(),
      })
    }
  } else {
    let widths = model.widths.map(width => (width * 20).round().to_int())
    if removing {
      ignore(widths.remove(c))
    } else {
      widths.insert(c + (if before { 0 } else { 1 }), widths[c])
    }
    let old_width = model.widths
      .iter()
      .fold(init=0.0, (sum, width) => sum + width)
    guard old_width <= flow.page.width - flow.page.left - flow.page.right else {
      @failure.reject(
        "unsupported-layout", "Table columns exceed the page content width",
      )
    }
    let fixed = tree
      .child(table, "tblPr")
      .bind(p => tree.child(p, "tblW"))
      .filter(id => {
        tree.nodes[id].attribute("type", uri=word_uri) == Some("dxa")
      })
    if fixed is Some(id) {
      let value = tree.nodes[id].attribute("w", uri=word_uri).unwrap_or("0")
      let width = @string.parse_int(value[:]) catch {
        _ => @failure.reject("invalid-table", "Invalid preferred table width")
      }
      if width > 0 {
        let total = widths
          .iter()
          .fold(init=0L, (sum, width) => sum + width.to_int64())
        let mut edge = 0L
        let mut previous = 0
        for i in 0..<widths.length() {
          edge += widths[i].to_int64()
          let end = ((edge * (old_width * 20).round().to_int64() + total / 2) /
          total).to_int()
          widths[i] = end - previous
          previous = end
        }
      }
    }
    guard widths.iter().all(width => width >= 240) else {
      @failure.reject(
        "invalid-operation", "Columns would be narrower than 12pt",
      )
    }
    guard widths.iter().fold(init=0L, (sum, width) => sum + width.to_int64()) <=
      ((flow.page.width - flow.page.left - flow.page.right) * 20)
      .floor()
      .to_int64() else {
      @failure.reject(
        "unsupported-layout", "Table columns exceed the page content width",
      )
    }
    let grid = tree.child(table, "tblGrid").unwrap()
    let markup = "<od:tblGrid xmlns:od=\"\{word_uri}\">" +
      widths.map(w => "<od:gridCol od:w=\"\{w}\"/>").join("") +
      "</od:tblGrid>"
    changes.push({ ..table_remove(tree, grid), xml: markup, })
    for row_index, row_cells in cells {
      if removing {
        changes.push(table_remove(tree, row_cells[c]))
      }
      for col, cell in row_cells {
        if removing && col == c {
          continue
        }
        let index = if removing && col > c {
          col - 1
        } else if !removing && col >= c + (if before { 0 } else { 1 }) {
          col + 1
        } else {
          col
        }
        let properties = tree.table_cell_properties(
          original,
          cell,
          widths[index],
        )
        if properties_change(tree, original, cell, "tcPr", properties)
          is Some(update) {
          changes.push(update)
        }
      }
      if !removing {
        let index = c + (if before { 0 } else { 1 })
        let node = tree.nodes[row_cells[c]]
        let template = if before {
          c
        } else {
          (c + 1).min(row_cells.length() - 1)
        }
        changes.push({
          node: rows[row_index],
          offset: (if before { node.start } else { node.end }) -
          tree.nodes[rows[row_index]].start,
          length: 0,
          xml: self.empty_table_cell(tree, row_cells[template], widths[index]),
        })
      }
    }
    if removing {
      target = model.rows[0][(c + 1).min(cells[0].length() - 1)][0].id
      if c == cells[0].length() - 1 {
        target = model.rows[0][c - 1][0].id
      }
    }
  }
  let (updated, edit) = original.edit_source(changes.items)
  let mut candidate = updated
  let edits = [edit]
  let inserted = WordTree::new(candidate)
  let new_first = if whole {
    if target < 0 {
      target = inserted.children[body][tree.children[body]
        .search(table)
        .unwrap()]
    }
    target
  } else {
    let new_rows = inserted.table_children(table, "tr")
    let first_cell = inserted.table_children(new_rows[0], "tc")[0]
    if target < 0 {
      let new_row = if row_edit { r + (if before { 0 } else { 1 }) } else { 0 }
      let new_col = if row_edit { 0 } else { c + (if before { 0 } else { 1 }) }
      target = inserted
        .child(inserted.table_children(new_rows[new_row], "tc")[new_col], "p")
        .unwrap()
    }
    inserted.child(first_cell, "p").unwrap()
  }
  if first.pageBreakBefore && new_first != first.id {
    let points = [new_first, first.id]
    for p in points {
      if !inserted.nodes.contains(p) {
        continue
      }
      let position = table_position(p)
      if self.format_paragraph_document(
          candidate,
          { anchor: position, focus: position, },
          ParagraphFormat::new(pageBreakBefore=Set(p == new_first)),
        )
        is Some((document, edit)) {
        candidate = document
        edits.push(edit)
      }
    }
  }
  let result = self.flow_from(candidate)
  if !whole {
    let changed = result.tables.iter().find_first(t => t.id == table).unwrap()
    guard changed.rows
      .iter()
      .all(row => {
        row
        .iter()
        .all(cell => cell.iter().all(p => p.readOnlyReason.is_empty()))
      }) else {
      @failure.reject(
        "protected-content", "Table formatting requires unsupported layout",
      )
    }
    affected.append(changed.rows.flatten().flatten().map(p => p.id))
  }
  let position = table_position(target)
  self.check_position_in(candidate, position)
  let bytes = edits
    .iter()
    .fold(init=0L, (sum, edit) => sum + edit.payload_bytes())
  guard bytes <= history_byte_limit.to_int64() else {
    @failure.reject("limit-exceeded", "Table history exceeds budget")
  }
  affected.push(target)
  self.commit_edit(
    {
      xml: edits,
      parts: Map([]),
      created: Map([]),
      before: self.selection,
      after: Some({ anchor: position, focus: position, }),
      paragraphs: affected,
      bytes: bytes.to_int(),
    },
    candidate,
  )
  self.edit_result(affected)
}
