///|
fn Session::delete_table_column(
  self : Session,
  selection : Selection,
  probe : @layout.TextProbe?,
  profile : Map[String, String],
  images : @layout.Images?,
) -> Json raise @failure.Failure {
  let document = self.document()
  let tree = WordTree::new(document)
  let selected = self.table_cell_range(tree, selection)
  let grid = selected
    .map(range => range.grid)
    .unwrap_or_else(() => self.table_grid(tree, selection))
  tree.check_table_structure(grid, columns=true)
  self.check_table_layout(self.flow(), grid.model, None, profile, None)
  let flow = self.flow()
  let available = table_column_width(flow, grid.model, probe, profile, images)
  let model = if probe is Some(probe) {
    grid.model.fit_widths(probe, profile, available)
  } else {
    grid.model
  }
  guard model.widths.fold(init=0.0, (sum, width) => sum + width) <= available else {
    @failure.reject(
      "unsupported-layout", "Table columns exceed the page content width",
    )
  }
  let positions : Array[Int] = [0]
  for width in model.widths {
    positions.push(positions.last().unwrap() + (width * 20).round().to_int())
  }
  let (left, right) = selected
    .map(range => range.column_bounds())
    .unwrap_or_else(() => {
      let left = grid.starts[grid.row][grid.column]
      (left, left + model.columnSpans[grid.row][grid.column])
    })
  let rows : Array[Int] = []
  let cells : Array[Array[Int]] = []
  let edges : Array[Array[Int]] = []
  let merges : Array[Array[String]] = []
  let mut previous : Map[(Int, Int), Int] = Map([])
  let mut first_deleted : (Int, Int)? = None
  for r, row in grid.cells {
    let kept : Array[Int] = []
    let boundaries : Array[Int] = [0]
    let states : Array[String] = []
    let current : Map[(Int, Int), Int] = Map([])
    for c, cell in row {
      tree.check_merge_cell(cell, self.main)
      let start = grid.starts[r][c]
      let end = start + model.columnSpans[r][c]
      if start < right && left < end {
        if first_deleted is None {
          first_deleted = Some((r, c))
        }
        continue
      }
      let x = boundaries.last().unwrap()
      let width = positions[end] - positions[start]
      let (owner_row, owner_column) = grid.owners[cell]
      let owner = grid.cells[owner_row][owner_column]
      let state = if model.rowSpans[r][c] == 0 &&
        previous.get((x, width)) == Some(owner) {
        "continue"
      } else if model.rowSpans[owner_row][owner_column] > 1 {
        "restart"
      } else {
        ""
      }
      kept.push(cell)
      states.push(state)
      boundaries.push(x + width)
      current[(x, width)] = owner
    }
    if kept.is_empty() || states.all(state => state == "continue") {
      continue
    }
    rows.push(r)
    cells.push(kept)
    edges.push(boundaries)
    merges.push(states)
    previous = current
  }
  let changes : TableChanges = {
    items: [],
    bytes: 0,
    limit: self.opc.budget.entry_bytes.min(history_byte_limit / 2),
  }
  if rows.is_empty() {
    tree.remove_body_table(grid.table, changes)
    return self.commit_table_structure(
      tree,
      grid,
      changes.items,
      0,
      0,
      true,
      probe,
      profile,
      images,
    )
  }
  let total = positions.last().unwrap()
  let maximum = edges.fold(init=0, (value, row) => {
    value.max(row.last().unwrap())
  })
  let fixed = tree
    .child(grid.table, "tblPr")
    .bind(p => tree.child(p, "tblW"))
    .map(id => {
      tree.nodes[id].attribute("type", uri=word_uri) == Some("dxa") &&
      tree.preferred_table_width(id).value > 0
    })
    .unwrap_or(false)
  let cuts : Array[Int] = [0]
  for row in edges {
    for c, point in row {
      let value = if fixed {
        ((point.to_int64() * total.to_int64() + maximum.to_int64() / 2) /
        maximum.to_int64()).to_int()
      } else {
        point
      }
      row[c] = value
      if !cuts.contains(value) {
        cuts.push(value)
      }
    }
  }
  cuts.sort()
  let count = cuts.length() - 1
  guard count <= 63 && rows.length().to_int64() * count.to_int64() <= 4096 else {
    @failure.reject("limit-exceeded", "Table exceeds row column or cell budget")
  }
  guard edges.all(row => {
    Array::makei(row.length() - 1, c => row[c + 1] - row[c]).all(width => {
      width >= 240
    })
  }) else {
    @failure.reject("invalid-operation", "Columns would be narrower than 12pt")
  }
  if tree.fitted_grid_change(
      document,
      grid.table,
      Array::makei(count, c => (cuts[c + 1] - cuts[c]).to_double() / 20),
    )
    is Some(change) {
    changes.push(change)
  }
  for r, row in grid.rows {
    guard rows.search(r) is Some(index) else {
      changes.push(table_remove(tree, row))
      continue
    }
    let kept = cells[index]
    let boundaries = edges[index]
    if tree.row_grid_change(
        document,
        row,
        count - cuts.search(boundaries.last().unwrap()).unwrap(),
      )
      is Some(change) {
      changes.push(change)
    }
    for cell in grid.cells[r] {
      if !kept.contains(cell) {
        changes.push(table_remove(tree, cell))
      }
    }
    for c, cell in kept {
      let span = cuts.search(boundaries[c + 1]).unwrap() -
        cuts.search(boundaries[c]).unwrap()
      let props = tree.column_cell_properties(
        document,
        cell,
        boundaries[c + 1] - boundaries[c],
        span,
        merges[index][c],
      )
      if properties_change(tree, document, cell, "tcPr", props) is Some(change) {
        changes.push(change)
      }
    }
  }
  let (deleted_row, deleted_cell) = first_deleted.unwrap()
  let mut target = rows.length() - 1
  for i in 0..<rows.length() {
    if rows[i] >= deleted_row {
      target = i
      break
    }
  }
  self.commit_table_structure(
    tree,
    grid,
    changes.items,
    target,
    deleted_cell.min(cells[target].length() - 1),
    false,
    probe,
    profile,
    images,
  )
}
