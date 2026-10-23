///|
fn Session::paste_grid_changes(
  self : Session,
  tree : WordTree,
  grid : TableGrid,
  rows : Int,
  columns : Int,
  probe : @layout.TextProbe,
  profile : Map[String, String],
  images : @layout.Images?,
  math~ : Bool = false,
  notes~ : Bool = false,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let old_columns = grid.model.widths.length()
  if rows == grid.rows.length() && columns == old_columns {
    return []
  }
  tree.check_table_structure(grid, columns=columns > old_columns)
  let document = self.document()
  let flow = self.flow()
  let fitted = grid.model.fit_widths(
    probe,
    profile,
    table_column_width(flow, grid.model, Some(probe), profile, images),
  )
  let old = fitted.widths.map(width => (width * 20).round().to_int())
  let widths = old.copy()
  for _ in old_columns..<columns {
    widths.push(old.last().unwrap())
  }
  if columns > old_columns {
    let total = old.fold(init=0L, (sum, width) => sum + width.to_int64())
    let expanded = widths.fold(init=0L, (sum, width) => sum + width.to_int64())
    let mut source = 0L
    let mut previous = 0L
    for index, width in widths {
      source += width.to_int64()
      let next = (source * total + expanded / 2) / expanded
      widths[index] = (next - previous).to_int()
      previous = next
    }
    guard widths[old_columns:].all(width => width >= 240) else {
      @failure.reject(
        "invalid-operation", "Pasted columns would be narrower than 12pt",
      )
    }
  }
  let changes : TableChanges = {
    items: [],
    bytes: 0,
    limit: self.opc.budget.entry_bytes.min(history_byte_limit / 2),
  }
  if columns > old_columns {
    if tree.fitted_grid_change(
        document,
        grid.table,
        widths.map(width => width.to_double() / 20),
      )
      is Some(change) {
      changes.push(change)
    }
    for r, cells in grid.cells {
      guard grid.model.columnSpans[r].fold(init=0, (sum, span) => sum + span) ==
        old_columns else {
        @failure.reject(
          "protected-content", "Growing a pasted table requires complete source rows",
        )
      }
      for c, cell in cells {
        let left = grid.starts[r][c]
        let span = grid.model.columnSpans[r][c]
        let width = widths[left:left + span].fold(init=0, (sum, width) => {
          sum + width
        })
        guard width >= 240 else {
          @failure.reject(
            "invalid-operation", "Pasted columns would be narrower than 12pt",
          )
        }
        let props = tree.column_cell_properties(
          document,
          cell,
          width,
          span,
          tree
          .child(cell, "tcPr")
          .bind(p => tree.child(p, "vMerge"))
          .map(id => {
            tree.nodes[id].attribute("val", uri=word_uri).unwrap_or("continue")
          })
          .unwrap_or(""),
        )
        if properties_change(tree, document, cell, "tcPr", props)
          is Some(change) {
          changes.push(change)
        }
      }
      let content = StringBuilder()
      let mut units = 0
      for column in old_columns..<columns {
        let xml = self.empty_table_cell(
          tree,
          cells.last().unwrap(),
          widths[column],
          fields=true,
          math~,
          notes~,
        )
        guard xml.length() <= changes.limit - units else {
          @failure.reject(
            "limit-exceeded", "Pasted column source exceeds budget",
          )
        }
        units += xml.length()
        content.write_string(xml)
      }
      let node = tree.nodes[grid.rows[r]]
      changes.push({
        node: node.id,
        offset: node.closing_start - node.start,
        length: 0,
        xml: content.to_string(),
      })
    }
  }
  if rows > grid.rows.length() {
    let last = grid.rows.length() - 1
    let properties = tree.copy_row_properties(
      document,
      grid.rows[last],
      after=Some(0),
    )
    let content = StringBuilder()
    let mut units = 0
    for _ in grid.rows.length()..<rows {
      let opening = "<od:tr xmlns:od=\"\{word_uri}\">\{properties}"
      units += opening.length()
      content.write_string(opening)
      for column in 0..<columns {
        let mut index = 0
        for c, start in grid.starts[last] {
          if start <= column.min(old_columns - 1) {
            index = c
          }
        }
        let xml = self.empty_table_cell(
          tree,
          grid.cells[last][index],
          widths[column],
          fields=true,
          math~,
          notes~,
        )
        guard xml.length() <= changes.limit - units else {
          @failure.reject("limit-exceeded", "Pasted row source exceeds budget")
        }
        units += xml.length()
        content.write_string(xml)
      }
      units += "</od:tr>".length()
      content.write_string("</od:tr>")
    }
    let table = tree.nodes[grid.table]
    changes.push({
      node: table.id,
      offset: table.closing_start - table.start,
      length: 0,
      xml: content.to_string(),
    })
  }
  changes.items
}

///|
fn Session::paste_table_cells(
  self : Session,
  revision : Int,
  selection : Selection,
  text : String,
  probe : @layout.TextProbe?,
  profile : Map[String, String],
  images : @layout.Images?,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  guard text.length() <= command_limit else {
    @failure.reject("limit-exceeded", "Table paste exceeds command text budget")
  }
  let values = @delimited.parse_tsv(text)
  let original = self.document()
  let tree = WordTree::new(original)
  let selected = self.table_cell_range(tree, selection, notes=true)
  let grid = selected
    .map(range => range.grid)
    .unwrap_or_else(() => self.table_grid(tree, selection, notes=true))
  let (top, column) = selected
    .map(range => grid.owners[range.owners[0]])
    .unwrap_or_else(() => grid.owners[grid.cells[grid.row][grid.column]])
  let left = grid.starts[top][column]
  let bottom = top + values.length()
  let right = left + values[0].length()
  let rows = bottom.max(grid.rows.length())
  let columns = right.max(grid.model.widths.length())
  guard rows <= 1000 &&
    columns <= 63 &&
    rows.to_int64() * columns.to_int64() <= 4096 else {
    @failure.reject(
      "limit-exceeded", "Pasted table exceeds row column or cell budget",
    )
  }
  for r in top..<bottom.min(grid.rows.length()) {
    for c, cell in grid.cells[r] {
      let start = grid.starts[r][c]
      let end = start + grid.model.columnSpans[r][c]
      if start < right && end > left {
        tree.check_merge_cell(cell, self.main, notes=true)
        guard grid.model.rowSpans[r][c] == 1 &&
          grid.model.columnSpans[r][c] == 1 else {
          @failure.reject(
            "protected-content", "A pasted matrix cannot overwrite merged cells",
          )
        }
      }
    }
  }
  let probe = probe.unwrap_or_else(() => {
    @failure.reject("missing-font", "Table pasting requires a text probe")
  })
  let changes = self.paste_grid_changes(
    tree,
    grid,
    rows,
    columns,
    probe,
    profile,
    images,
    notes=true,
  )
  let mut candidate = original
  let steps : Array[@xml.Edit] = []
  let mut bytes = 0
  if !changes.is_empty() {
    let (document, edit) = original.edit_source(changes)
    bytes = edit_bytes(edit)
    steps.push(edit)
    candidate = document
  }
  let expanded_tree = WordTree::new(candidate)
  let expanded = self.flow_from(candidate).tables
    .iter()
    .find_first(table => table.id == grid.table)
    .unwrap()
  let targets : Array[(Int, String)] = []
  let mut first : Int? = None
  for r in top..<bottom {
    let row = expanded_tree.table_children(grid.table, "tr")[r]
    let cells = expanded_tree.table_children(row, "tc")
    let mut start = 0
    let mut count = 0
    for c, cell in cells {
      if start >= left && start < right {
        guard expanded.columnSpans[r][c] == 1 && expanded.rowSpans[r][c] == 1 else {
          @failure.reject(
            "protected-content", "Pasted values require ordinary target cells",
          )
        }
        if first is None {
          first = Some(cell)
        }
        let value = values[r - top][start - left]
        let before = expanded.rows[r][c]
          .map(p => p.spans.map(span => span.text).join(""))
          .join("\n")
        if before != value ||
          expanded_tree
          .descendants(cell)
          .any(id => note_reference(expanded_tree.nodes[id])) {
          targets.push((cell, value))
        }
        count += 1
      }
      start += expanded.columnSpans[r][c]
    }
    guard count == values[0].length() else {
      @failure.reject(
        "protected-content", "Pasted values cross missing source cells",
      )
    }
  }
  if targets.is_empty() && steps.is_empty() {
    return self.edit_state()
  }
  let mut work = 0L
  let affected = grid.cells
    .flatten()
    .map(cell => tree.table_children(cell, "p"))
    .flatten()
  // shortcut: Reparse per changed cell within 64 Mi units; batch text patches if larger matrices need them.
  for index = targets.length() - 1; index >= 0; index = index - 1 {
    let (cell, value) = targets[index]
    work += candidate.source().length().to_int64() +
      value.length().to_int64() * 6
    guard work <= 67108864L else {
      @failure.reject("limit-exceeded", "Table paste work exceeds budget")
    }
    let current = WordTree::new(candidate)
    let selection = current.cell_contents_selection(cell, docx_texts(current))
    let prepared = self.prepare_structural_range_in(
      candidate,
      selection,
      value,
      notes=true,
    )
    guard prepared.edit.bytes <= history_byte_limit - bytes else {
      @failure.reject("limit-exceeded", "Table paste history exceeds budget")
    }
    bytes += prepared.edit.bytes
    steps.append(prepared.edit.xml)
    affected.append(prepared.edit.paragraphs)
    candidate = prepared.document
  }
  let flow = self.flow_from(candidate)
  let table = flow.tables
    .iter()
    .find_first(table => table.id == grid.table)
    .unwrap()
  self.check_table_layout(flow, table, Some(probe), profile, images)
  affected.append(table.rows.flatten().flatten().map(p => p.id))
  let current = WordTree::new(candidate)
  let focus = {
    ..current.cell_contents_selection(first.unwrap(), docx_texts(current)).focus,
    affinity: "after",
  }
  self.commit_edit(
    {
      xml: steps,
      parts: Map([]),
      created: Map([]),
      created_media: Map([]),
      before: self.selection,
      after: Some({ anchor: focus, focus, }),
      paragraphs: affected,
      bytes,
    },
    candidate,
  )
  self.edit_result(affected)
}
