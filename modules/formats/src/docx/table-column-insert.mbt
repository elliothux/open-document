///|
fn WordTree::column_cell_properties(
  self : WordTree,
  document : @xml.Document,
  cell : Int,
  width : Int,
  span : Int,
  merge : String,
) -> String raise @failure.Failure {
  let props = self.merged_cell_properties(document, cell, width, span, merge)
  if self.child(cell, "tcPr").bind(p => self.child(p, "tcW")) is Some(id) &&
    self.nodes[id].attribute("type", uri=word_uri) is Some("auto" | "nil") {
    return props.replace(
      old="<od:tcW od:type=\"dxa\" od:w=\"\{width}\"/>",
      new=self.standalone_markup(document, id),
    )
  }
  props
}

///|
fn Session::insert_table_column(
  self : Session,
  selection : Selection,
  before : Bool,
  probe : @layout.TextProbe?,
  profile : Map[String, String],
  images : @layout.Images?,
) -> Json raise @failure.Failure {
  let document = self.document()
  let tree = WordTree::new(document)
  let grid = self.table_grid(tree, selection)
  tree.check_table_structure(grid, columns=true)
  let flow = self.flow()
  let available = flow.columns.width(flow.page)
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
  let start = grid.starts[grid.row][grid.column]
  let end = start + model.columnSpans[grid.row][grid.column]
  let size = positions[end] - positions[start]
  let boundary = if before { start } else { end }
  let total = positions.last().unwrap()
  let fixed = tree
    .child(grid.table, "tblPr")
    .bind(p => tree.child(p, "tblW"))
    .map(id => {
      tree.nodes[id].attribute("type", uri=word_uri) == Some("dxa") &&
      tree.preferred_table_width(id, available) > 0
    })
    .unwrap_or(false)
  let next_total = if fixed { total } else { total + size }
  guard next_total.to_double() <= available * 20 else {
    @failure.reject(
      "unsupported-layout", "Table columns exceed the page content width",
    )
  }
  let scale = fn(point : Int) {
    if fixed {
      ((point.to_int64() * total.to_int64() + (total + size).to_int64() / 2) /
      (total + size).to_int64()).to_int()
    } else {
      point
    }
  }
  let insertions : Array[Int] = []
  let row_edges : Array[Array[Int]] = []
  let cuts : Array[Int] = [0]
  for r, cells in grid.cells {
    let mut index = 0
    for c in 0..<cells.length() {
      let left = grid.starts[r][c]
      let right = left + model.columnSpans[r][c]
      if before && left <= boundary {
        index = c
      } else if !before && right <= boundary {
        index = c + 1
      }
    }
    insertions.push(index)
    let edges : Array[Int] = [0]
    let mut point = 0
    for c in 0..<=cells.length() {
      if c == index {
        point += size
        edges.push(scale(point))
      }
      if c < cells.length() {
        let left = grid.starts[r][c]
        point += positions[left + model.columnSpans[r][c]] - positions[left]
        edges.push(scale(point))
      }
    }
    row_edges.push(edges)
    for edge in edges {
      if !cuts.contains(edge) {
        cuts.push(edge)
      }
    }
  }
  cuts.sort()
  let count = cuts.length() - 1
  guard count <= 63 && grid.rows.length().to_int64() * count.to_int64() <= 4096 else {
    @failure.reject("limit-exceeded", "Table exceeds row column or cell budget")
  }
  let widths = Array::makei(count, i => cuts[i + 1] - cuts[i])
  guard row_edges.all(edges => {
    Array::makei(edges.length() - 1, i => edges[i + 1] - edges[i]).all(width => {
      width >= 240
    })
  }) else {
    @failure.reject("invalid-operation", "Columns would be narrower than 12pt")
  }
  let changes : TableChanges = {
    items: [],
    bytes: 0,
    limit: self.opc.budget.entry_bytes.min(history_byte_limit / 2),
  }
  if tree.fitted_grid_change(
      document,
      grid.table,
      widths.map(w => w.to_double() / 20),
    )
    is Some(change) {
    changes.push(change)
  }
  let mut previous_template : Int? = None
  let mut previous_bounds : (Int, Int)? = None
  for r, cells in grid.cells {
    let index = insertions[r]
    let edges = row_edges[r]
    if tree.row_grid_change(
        document,
        grid.rows[r],
        count - cuts.search(edges.last().unwrap()).unwrap(),
      )
      is Some(change) {
      changes.push(change)
    }
    for c, cell in cells {
      tree.check_merge_cell(cell, self.main)
      let position = c + (if c >= index { 1 } else { 0 })
      let span = cuts.search(edges[position + 1]).unwrap() -
        cuts.search(edges[position]).unwrap()
      let merge = tree
        .child(cell, "tcPr")
        .bind(p => tree.child(p, "vMerge"))
        .map(id => {
          tree.nodes[id].attribute("val", uri=word_uri).unwrap_or("continue")
        })
        .unwrap_or("")
      let props = tree.column_cell_properties(
        document,
        cell,
        edges[position + 1] - edges[position],
        span,
        merge,
      )
      if properties_change(tree, document, cell, "tcPr", props) is Some(change) {
        changes.push(change)
      }
    }
    let template = cells[index.min(cells.length() - 1)]
    let (owner_row, owner_column) = grid.owners[template]
    let owner = grid.cells[owner_row][owner_column]
    let bounds = (edges[index], edges[index + 1])
    // Copied continuation properties may only join the same original owner.
    let merge = if owner_row < r &&
      previous_template == Some(owner) &&
      previous_bounds == Some(bounds) {
      "continue"
    } else if model.rowSpans[owner_row][owner_column] > 1 {
      "restart"
    } else {
      ""
    }
    previous_template = Some(owner)
    previous_bounds = Some(bounds)
    let span = cuts.search(bounds.1).unwrap() - cuts.search(bounds.0).unwrap()
    let width = bounds.1 - bounds.0
    let props = tree.column_cell_properties(
      document, template, width, span, merge,
    )
    let node = tree.nodes[cells[index.min(cells.length() - 1)]]
    changes.push({
      node: grid.rows[r],
      offset: (if index == cells.length() { node.end } else { node.start }) -
      tree.nodes[grid.rows[r]].start,
      length: 0,
      xml: self.split_empty_cell(tree, template, width, props),
    })
  }
  self.commit_table_structure(
    tree,
    grid,
    changes.items,
    0,
    insertions[0],
    false,
    probe,
    profile,
    images,
  )
}
