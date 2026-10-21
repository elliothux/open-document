///|
priv struct TableGrid {
  table : Int
  rows : Array[Int]
  cells : Array[Array[Int]]
  starts : Array[Array[Int]]
  owners : Map[Int, (Int, Int)]
  model : @layout.Table
  row : Int
  column : Int
}

///|
fn Session::table_grid(
  self : Session,
  tree : WordTree,
  selection : Selection,
  fields~ : Bool = false,
) -> TableGrid raise @failure.Failure {
  let range = self.paragraph_range(tree, selection, structural=true, fields~)
  let cell = tree.nodes[range.start.paragraph].parent
  guard tree.nodes[cell].uri == word_uri && tree.nodes[cell].name == "tc" else {
    @failure.reject("invalid-operation", "Select a table cell first")
  }
  ignore(self.editable_page_section(tree))
  let row = tree.nodes[cell].parent
  let table = tree.nodes[row].parent
  let model = self.flow_from(self.document()).tables
    .iter()
    .find_first(t => t.id == table)
    .unwrap()
  let r = tree.table_children(table, "tr").search(row).unwrap()
  let c = tree.table_children(row, "tc").search(cell).unwrap()
  read_table_grid(tree, model, r, c)
}

///|
fn read_table_grid(
  tree : WordTree,
  model : @layout.Table,
  row : Int,
  column : Int,
) -> TableGrid raise @failure.Failure {
  let table = model.id
  let rows = tree.table_children(table, "tr")
  let cells = rows.map(row => tree.table_children(row, "tc"))
  guard rows.length() == model.rows.length() else {
    @failure.reject(
      "protected-content", "Unknown table rows or cells prevent grid editing",
    )
  }
  for r, row in cells {
    guard row.length() == model.rows[r].length() else {
      @failure.reject(
        "protected-content", "Unknown table rows or cells prevent grid editing",
      )
    }
  }
  let starts : Array[Array[Int]] = []
  let owners : Map[Int, (Int, Int)] = Map([])
  let mut previous : Map[(Int, Int), (Int, Int)] = Map([])
  for r, row in cells {
    let positions : Array[Int] = []
    let current : Map[(Int, Int), (Int, Int)] = Map([])
    let mut start = 0
    for c, id in row {
      let span = model.columnSpans[r][c]
      let owner = if model.rowSpans[r][c] == 0 {
        previous
        .get((start, span))
        .unwrap_or_error(
          @failure.Failure(
            code="invalid-table",
            part="",
            offset=id,
            message="Merged continuation has no matching owner",
          ),
        )
      } else {
        (r, c)
      }
      owners[id] = owner
      current[(start, span)] = owner
      positions.push(start)
      start += span
    }
    previous = current
    starts.push(positions)
  }
  { table, rows, cells, starts, owners, model, row, column, }
}

///|
fn WordTree::check_merge_cell(
  self : WordTree,
  cell : Int,
  part : String,
  pictures~ : Bool = false,
  fields~ : Bool = false,
) -> Unit raise @failure.Failure {
  guard self.child(cell, "p") is Some(_) else {
    @failure.reject(
      "protected-content", "Table cells without paragraphs are protected",
    )
  }
  guard self.nodes[cell].attributes
    .iter()
    .all(a => {
      a.uri == word_uri &&
      ["rsidR", "rsidRPr", "rsidDel", "rsidTr"].contains(a.name)
    }) &&
    self.children[cell].all(id => {
      self.nodes[id].uri == word_uri &&
      ["tcPr", "p"].contains(self.nodes[id].name)
    }) else {
    @failure.reject(
      "protected-content", "Cell extensions require table identity support",
    )
  }
  for p in self.table_children(cell, "p") {
    self.check_editable_paragraph(p, part~, pictures~, fields~)
    self.check_structure_paragraph(p, running=fields)
  }
  guard self.table_children(cell, "tcPr").length() <= 1 else {
    @failure.reject("protected-content", "Duplicate cell properties")
  }
  if self.child(cell, "tcPr") is Some(props) {
    for child in self.children[props] {
      let node = self.nodes[child]
      if node.uri == word_uri && node.name == "tcBorders" {
        ignore(self.read_borders(props, "tcBorders"))
        continue
      }
      if node.uri == word_uri && node.name == "tcMar" {
        guard self.table_children(props, "tcMar").length() == 1 else {
          @failure.reject("protected-content", "Duplicate cell margins")
        }
        ignore(
          self.table_margins(child, { top: 0, right: 0, bottom: 0, left: 0, }),
        )
        continue
      }
      let attributes = match node.name {
        "tcW" => ["type", "w"]
        "shd" => ["val", "color", "fill"]
        "gridSpan" | "vMerge" | "vAlign" => ["val"]
        _ =>
          @failure.reject(
            "protected-content", "Cell properties require merging support",
          )
      }
      guard node.uri == word_uri &&
        self.table_children(props, node.name).length() == 1 &&
        self.children[child].is_empty() &&
        node.text.trim().is_empty() &&
        node.attributes.all(a => {
          a.uri == word_uri && attributes.contains(a.name)
        }) else {
        @failure.reject("protected-content", "Unknown merged cell properties")
      }
    }
  }
}

///|
fn WordTree::merged_cell_properties(
  self : WordTree,
  document : @xml.Document,
  cell : Int,
  width : Int,
  columns : Int,
  state : String,
) -> String raise @failure.Failure {
  let original = self.table_cell_properties(document, cell, width)
  let extra = (if columns > 1 {
      "<od:gridSpan od:val=\"\{columns}\"/>"
    } else {
      ""
    }) +
    (if state.is_empty() { "" } else { "<od:vMerge od:val=\"\{state}\"/>" })
  original.replace(old="</od:tcPr>", new=extra + "</od:tcPr>")
}

///|
fn Session::commit_table_merge(
  self : Session,
  tree : WordTree,
  grid : TableGrid,
  changes : Array[@xml.SourceChange],
  probe? : @layout.TextProbe,
  profile~ : Map[String, String] = Map([]),
  images? : @layout.Images,
) -> Json raise @failure.Failure {
  let (candidate, edit) = self.document().edit_source(changes)
  let updated = WordTree::new(candidate)
  let cell = updated.table_children(grid.rows[grid.row], "tc")[grid.column]
  let paragraph = updated.child(cell, "p").unwrap()
  let result = self.flow_from(candidate)
  let model = result.tables.iter().find_first(t => t.id == grid.table).unwrap()
  self.check_table_layout(result, model, probe, profile, images)
  let before = grid.cells
    .flatten()
    .map(cell => tree.table_children(cell, "p"))
    .flatten()
  let affected = [..before, ..model.rows.flatten().flatten().map(p => p.id)]
  let bytes = edit.payload_bytes()
  guard bytes <= history_byte_limit.to_int64() else {
    @failure.reject("limit-exceeded", "Table merge history exceeds budget")
  }
  let position = table_position(paragraph)
  self.commit_edit(
    {
      xml: [edit],
      parts: Map([]),
      created: Map([]),
      created_media: Map([]),
      before: self.selection,
      after: Some({ anchor: position, focus: position, }),
      paragraphs: affected,
      bytes: bytes.to_int(),
    },
    candidate,
  )
  self.edit_result(affected)
}

///|
fn Session::merge_table_cells(
  self : Session,
  revision : Int,
  selection : Selection,
  rows : Int,
  columns : Int,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  guard rows >= 1 &&
    rows <= 1000 &&
    columns >= 1 &&
    columns <= 63 &&
    rows.to_int64() * columns.to_int64() <= 4096L else {
    @failure.reject("invalid-operation", "Invalid table merge dimensions")
  }
  let document = self.document()
  let tree = WordTree::new(document)
  let selected = self.table_cell_range(tree, selection)
  let original = selected
    .map(range => range.grid)
    .unwrap_or_else(() => self.table_grid(tree, selection))
  let first = selected.map(range => range.top).unwrap_or(original.row)
  let left = selected
    .map(range => range.left)
    .unwrap_or_else(() => original.starts[first][original.column])
  if selected is Some(range) {
    guard rows == range.bottom - first && columns == range.right - left else {
      @failure.reject(
        "invalid-operation", "Merge dimensions must match selected cells",
      )
    }
  }
  guard original.starts[first].search(left) is Some(column) else {
    @failure.reject(
      "invalid-operation", "Merge rectangle cuts an existing merged cell",
    )
  }
  let grid = { ..original, row: first, column, }
  let bottom = first + rows
  let right = left + columns
  guard bottom <= grid.rows.length() && right <= grid.model.widths.length() else {
    @failure.reject("invalid-operation", "Merge rectangle exceeds table grid")
  }
  if grid.model.rowSpans[first][grid.column] == rows &&
    grid.model.columnSpans[first][grid.column] == columns {
    return self.edit_state()
  }
  let selected : Array[Array[Int]] = []
  for r in first..<bottom {
    let indices : Array[Int] = []
    for c, cell in grid.cells[r] {
      let start = grid.starts[r][c]
      let end = start + grid.model.columnSpans[r][c]
      if start >= right || end <= left {
        continue
      }
      let (owner, _) = grid.owners[cell]
      guard start >= left &&
        end <= right &&
        owner >= first &&
        (
          grid.model.rowSpans[r][c] == 0 ||
          r + grid.model.rowSpans[r][c] <= bottom
        ) else {
        @failure.reject(
          "invalid-operation", "Merge rectangle cuts an existing merged cell",
        )
      }
      tree.check_merge_cell(cell, self.main)
      indices.push(c)
    }
    guard !indices.is_empty() else {
      @failure.reject("invalid-operation", "Merge rectangle has no cells")
    }
    selected.push(indices)
  }
  let limit = self.opc.budget.entry_bytes.min(history_byte_limit / 2)
  let changes : TableChanges = { items: [], bytes: 0, limit, }
  let content = StringBuilder()
  let mut units = 0
  let anchor = grid.cells[first][grid.column]
  for offset, indices in selected {
    let r = first + offset
    for c in indices {
      let cell = grid.cells[r][c]
      if cell == anchor || grid.model.rowSpans[r][c] == 0 {
        continue
      }
      for p in tree.table_children(cell, "p") {
        let markup = tree.standalone_markup(document, p)
        guard markup.length() <= limit - units else {
          @failure.reject(
            "limit-exceeded", "Merged content exceeds history budget",
          )
        }
        units += markup.length()
        content.write_string(markup)
      }
    }
  }
  if !content.to_string().is_empty() {
    let node = tree.nodes[anchor]
    changes.push({
      node: anchor,
      offset: node.closing_start - node.start,
      length: 0,
      xml: content.to_string(),
    })
  }
  let width = grid.model.widths[left:right]
    .iter()
    .fold(init=0.0, (sum, value) => sum + value)
  for offset, indices in selected {
    let r = first + offset
    let cell = grid.cells[r][indices[0]]
    let state = if rows == 1 {
      ""
    } else if offset == 0 {
      "restart"
    } else {
      "continue"
    }
    let properties = tree.merged_cell_properties(
      document,
      cell,
      (width * 20).round().to_int(),
      columns,
      state,
    )
    if properties_change(tree, document, cell, "tcPr", properties)
      is Some(change) {
      changes.push(change)
    }
    if offset > 0 {
      let paragraphs = tree.table_children(cell, "p")
      for index, p in paragraphs {
        changes.push({
          ..table_remove(tree, p),
          xml: if index == 0 {
            "<od:p xmlns:od=\"\{word_uri}\"/>"
          } else {
            ""
          },
        })
      }
    }
    for c in indices[1:] {
      changes.push(table_remove(tree, grid.cells[r][c]))
    }
  }
  self.commit_table_merge(tree, grid, changes.items)
}

///|
fn Session::unmerge_table_cells(
  self : Session,
  revision : Int,
  selection : Selection,
  probe : @layout.TextProbe?,
  profile : Map[String, String],
  images : @layout.Images?,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let document = self.document()
  let tree = WordTree::new(document)
  let selected = self.table_cell_range(tree, selection)
  let original = selected
    .map(range => range.grid)
    .unwrap_or_else(() => self.table_grid(tree, selection))
  let owners = selected
    .map(range => range.owners)
    .unwrap_or([original.cells[original.row][original.column]])
  let (row, column) = original.owners[owners[0]]
  let grid = { ..original, row, column, }
  let changes : TableChanges = {
    items: [],
    bytes: 0,
    limit: self.opc.budget.entry_bytes.min(history_byte_limit / 2),
  }
  for owner in owners {
    let (r, c) = grid.owners[owner]
    let rows = grid.model.rowSpans[r][c]
    let columns = grid.model.columnSpans[r][c]
    if rows == 1 && columns == 1 {
      continue
    }
    let left = grid.starts[r][c]
    for row in r..<(r + rows) {
      let col = grid.starts[row].search(left).unwrap()
      let cell = grid.cells[row][col]
      tree.check_merge_cell(cell, self.main)
      let properties = tree.merged_cell_properties(
        document,
        cell,
        (grid.model.widths[left] * 20).round().to_int(),
        1,
        "",
      )
      if properties_change(tree, document, cell, "tcPr", properties)
        is Some(change) {
        changes.push(change)
      }
      let content = StringBuilder()
      let mut units = 0
      for column in 1..<columns {
        let markup = self.empty_table_cell(
          tree,
          cell,
          (grid.model.widths[left + column] * 20).round().to_int(),
        )
        guard markup.length() <= changes.limit - units else {
          @failure.reject(
            "limit-exceeded", "Unmerged cells exceed history budget",
          )
        }
        units += markup.length()
        content.write_string(markup)
      }
      if units > 0 {
        let node = tree.nodes[cell]
        changes.push({
          node: node.parent,
          offset: node.end - tree.nodes[node.parent].start,
          length: 0,
          xml: content.to_string(),
        })
      }
    }
  }
  if changes.items.is_empty() {
    return self.edit_state()
  }
  self.commit_table_merge(tree, grid, changes.items, probe?, profile~, images?)
}
