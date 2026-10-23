///|
fn Session::split_table(
  self : Session,
  revision : Int,
  selection : Selection,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let document = self.document()
  let tree = WordTree::new(document)
  let grid = self.table_grid(tree, selection, notes=true)
  guard grid.row > 0 else {
    @failure.reject(
      "invalid-operation", "Select a row after the first table row",
    )
  }
  let table = tree.nodes[grid.table]
  let body = table.parent
  guard tree.nodes[body].uri == word_uri && tree.nodes[body].name == "body" else {
    @failure.reject("protected-content", "Only body tables can be split")
  }
  for id in [grid.table, ..grid.rows] {
    let allowed = if id == grid.table {
      ["tblPr", "tblGrid", "tr"]
    } else {
      ["trPr", "tc"]
    }
    guard tree.nodes[id].attributes.all(a => {
        a.uri == word_uri &&
        ["rsidR", "rsidRPr", "rsidDel", "rsidTr"].contains(a.name)
      }) &&
      tree.children[id].all(child => {
        tree.nodes[child].uri == word_uri &&
        allowed.contains(tree.nodes[child].name)
      }) else {
      @failure.reject(
        "protected-content", "Unknown table structure prevents splitting",
      )
    }
    for name in ["tblPr", "tblGrid", "trPr"] {
      guard tree.table_children(id, name).length() <= 1 else {
        @failure.reject("protected-content", "Duplicate table properties")
      }
    }
  }
  for cell in grid.cells.flatten() {
    tree.check_merge_cell(cell, self.main, notes=true)
  }
  for name in ["tblPr", "tblGrid"] {
    if tree.child(grid.table, name) is Some(id) {
      guard tree.nodes[id].attributes.is_empty() &&
        tree.nodes[id].text.trim().is_empty() else {
        @failure.reject(
          "protected-content", "Unknown table property container prevents copying",
        )
      }
      if name == "tblGrid" {
        guard tree.children[id].all(child => {
          let node = tree.nodes[child]
          node.uri == word_uri &&
          node.name == "gridCol" &&
          tree.children[child].is_empty() &&
          node.text.trim().is_empty() &&
          node.attributes.all(a => a.uri == word_uri && a.name == "w")
        }) else {
          @failure.reject(
            "protected-content", "Unknown table grid prevents copying",
          )
        }
      }
    }
  }
  let limit = self.opc.budget.entry_bytes.min(history_byte_limit / 2)
  let changes : TableChanges = { items: [], bytes: 0, limit, }
  let opening = StringBuilder()
  opening.write_string("</\{table.qualified}><od:p xmlns:od=\"\{word_uri}\"/>")
  opening.write_string(structure_opening(table))
  for name in ["tblPr", "tblGrid"] {
    if tree.child(grid.table, name) is Some(id) {
      let copy = tree.standalone_markup(document, id)
      guard copy.length() <= limit - opening.to_string().length() else {
        @failure.reject(
          "limit-exceeded", "Split table properties exceed history budget",
        )
      }
      opening.write_string(copy)
    }
  }
  // Insert a boundary rather than moving rows, retaining every surviving node identity.
  changes.push({
    node: body,
    offset: tree.nodes[grid.rows[grid.row]].start - tree.nodes[body].start,
    length: 0,
    xml: opening.to_string(),
  })
  for column, cell in grid.cells[grid.row] {
    if grid.model.rowSpans[grid.row][column] != 0 {
      continue
    }
    let (row, owner_column) = grid.owners[cell]
    let owner = grid.cells[row][owner_column]
    let start = grid.starts[grid.row][column]
    let span = grid.model.columnSpans[grid.row][column]
    let width = (grid.model.widths[start:start + span]
      .iter()
      .fold(init=0.0, (sum, width) => sum + width) *
      20)
      .round()
      .to_int()
    let properties = tree.table_cell_properties(document, owner, width)
    let merged = tree.merged_cell_properties(
      document, owner, width, span, "restart",
    )
    let empty = self
      .empty_table_cell(tree, owner, width, notes=true)
      .replace(old=properties[:], new=merged[:])
    // A crossing merge keeps its content above the cut and starts an empty cell below.
    changes.push({ ..table_remove(tree, cell), xml: empty, })
  }
  let (candidate, edit) = document.edit_source(changes.items)
  let updated = WordTree::new(candidate)
  let lower = updated.nodes[grid.rows[grid.row]].parent
  let first = updated.table_children(grid.rows[grid.row], "tc")[0]
  let target = updated.child(first, "p").unwrap()
  let flow = self.flow_from(candidate)
  let affected = grid.cells
    .flatten()
    .map(cell => tree.table_children(cell, "p"))
    .flatten()
  for model in flow.tables {
    if model.id != grid.table && model.id != lower {
      continue
    }
    let paragraphs = model.rows.flatten().flatten()
    guard paragraphs.all(p => p.readOnlyReason.is_empty()) else {
      @failure.reject(
        "protected-content", "Split table formatting requires unsupported layout",
      )
    }
    affected.append(paragraphs.map(p => p.id))
  }
  let siblings = updated.children[body]
  affected.push(siblings[siblings.search(lower).unwrap() - 1])
  let bytes = edit.payload_bytes()
  guard bytes <= history_byte_limit.to_int64() else {
    @failure.reject("limit-exceeded", "Split table history exceeds budget")
  }
  let position = table_position(target)
  self.check_position_in(candidate, position)
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
