///|
fn WordTree::split_cell_properties(
  self : WordTree,
  document : @xml.Document,
  cell : Int,
  span : Int,
  merge : String,
  part : Int,
  count : Int,
) -> String raise @failure.Failure {
  let props = self.child(cell, "tcPr")
  if props is Some(id) {
    let node = self.nodes[id]
    let source = document.source()[node.start:node.end]
    guard node.attributes.is_empty() &&
      node.text.trim().is_empty() &&
      !source.contains("<!--") &&
      !source.contains("<?") else {
      @failure.reject(
        "protected-content", "Unknown cell property markup prevents splitting",
      )
    }
  }
  let fields : Array[String] = []
  if props.bind(id => self.child(id, "tcW")) is Some(id) {
    let node = self.nodes[id]
    let kind = node.attribute("type", uri=word_uri).unwrap_or("dxa")
    if count > 1 && ["dxa", "pct"].contains(kind) {
      let value = @string.parse_int(
        node.attribute("w", uri=word_uri).unwrap_or("0"),
      ) catch {
        _ => @failure.reject("protected-content", "Invalid split cell width")
      }
      let width = value.to_int64() * (part + 1).to_int64() / count.to_int64() -
        value.to_int64() * part.to_int64() / count.to_int64()
      fields.push("<od:tcW od:type=\"\{kind}\" od:w=\"\{width}\"/>")
    } else {
      fields.push(self.standalone_markup(document, id))
    }
  }
  if span > 1 {
    fields.push("<od:gridSpan od:val=\"\{span}\"/>")
  }
  if !merge.is_empty() {
    fields.push("<od:vMerge od:val=\"\{merge}\"/>")
  }
  if props is Some(id) {
    for child in self.children[id] {
      if !["tcW", "gridSpan", "vMerge"].contains(self.nodes[child].name) {
        fields.push(self.standalone_markup(document, child))
      }
    }
  }
  "<od:tcPr xmlns:od=\"\{word_uri}\">\{fields.join("")}</od:tcPr>"
}

///|
fn Session::split_empty_cell(
  self : Session,
  tree : WordTree,
  cell : Int,
  width : Int,
  props : String,
) -> String raise @failure.Failure {
  self
  .empty_table_cell(tree, cell, width)
  .replace(
    old=tree.table_cell_properties(self.document(), cell, width)[:],
    new=props[:],
  )
}

///|
fn Session::split_table_cell(
  self : Session,
  revision : Int,
  selection : Selection,
  rows : Int,
  columns : Int,
  probe : @layout.TextProbe?,
  profile : Map[String, String],
  images : @layout.Images?,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  guard rows >= 1 &&
    rows <= 1000 &&
    columns >= 1 &&
    columns <= 63 &&
    rows.to_int64() * columns.to_int64() <= 4096 else {
    @failure.reject("invalid-operation", "Invalid split cell dimensions")
  }
  let document = self.document()
  let tree = WordTree::new(document)
  let selected = self.table_grid(tree, selection)
  let (first, c) = selected.owners[selected.cells[selected.row][selected.column]]
  let grid = { ..selected, row: first, column: c, }
  if rows == 1 && columns == 1 {
    return self.edit_state()
  }
  let height = grid.model.rowSpans[first][c]
  // ONLYOFFICE SplitTableCells partitions an existing vertical merge along its row groups.
  guard height == 1 || (rows <= height && height % rows == 0) else {
    @failure.reject(
      "invalid-operation", "Split row count must divide the existing vertical merge",
    )
  }
  let extra_rows = if height == 1 { rows - 1 } else { 0 }
  let probe = probe.unwrap_or_else(() => {
    @failure.reject("missing-font", "Cell splitting requires a text probe")
  })
  let flow = self.flow()
  let fitted = grid.model.fit_widths(
    probe,
    profile,
    flow.columns.width(flow.page),
  )
  let positions : Array[Int] = [0]
  for width in fitted.widths {
    positions.push(positions.last().unwrap() + (width * 20).round().to_int())
  }
  let left = grid.starts[first][c]
  let right = left + grid.model.columnSpans[first][c]
  let size = positions[right] - positions[left]
  guard size >= columns else {
    @failure.reject(
      "invalid-operation", "Split columns are narrower than one twip",
    )
  }
  let cuts = Array::makei(columns + 1, i => {
    positions[left] +
    (size.to_int64() * i.to_int64() / columns.to_int64()).to_int()
  })
  let refined = positions.copy()
  for point in cuts {
    if !refined.contains(point) {
      refined.push(point)
    }
  }
  refined.sort()
  let count = refined.length() - 1
  guard grid.rows.length() + extra_rows <= 1000 &&
    count <= 63 &&
    (grid.rows.length() + extra_rows).to_int64() * count.to_int64() <= 4096 else {
    @failure.reject(
      "limit-exceeded", "Split table exceeds row column or cell budget",
    )
  }
  let widths = Array::makei(count, i => {
    (refined[i + 1] - refined[i]).to_double() / 20
  })
  let changes : TableChanges = {
    items: [],
    bytes: 0,
    limit: self.opc.budget.entry_bytes.min(history_byte_limit / 2),
  }
  if tree.fitted_grid_change(document, grid.table, widths) is Some(change) {
    changes.push(change)
  }
  let target = grid.cells[first][c]
  for r, row in grid.cells {
    let end = grid.model.columnSpans[r].fold(init=0, (sum, span) => sum + span)
    if tree.row_grid_change(
        document,
        grid.rows[r],
        count - refined.search(positions[end]).unwrap(),
      )
      is Some(change) {
      changes.push(change)
    }
    for col, cell in row {
      let start = grid.starts[r][col]
      let end = start + grid.model.columnSpans[r][col]
      let span = refined.search(positions[end]).unwrap() -
        refined.search(positions[start]).unwrap()
      let owner = grid.owners[cell]
      let splitting = owner == (first, c)
      let extend_row = extra_rows > 0 &&
        r == first &&
        grid.model.rowSpans[r][col] == 1 &&
        !splitting
      if !splitting && !extend_row && span == grid.model.columnSpans[r][col] {
        continue
      }
      tree.check_merge_cell(cell, self.main)
      let merge = if splitting {
        if height == 1 || height / rows == 1 {
          ""
        } else if (r - first) % (height / rows) == 0 {
          "restart"
        } else {
          "continue"
        }
      } else if extend_row {
        "restart"
      } else {
        tree
        .child(cell, "tcPr")
        .bind(id => tree.child(id, "vMerge"))
        .map(id => {
          tree.nodes[id].attribute("val", uri=word_uri).unwrap_or("continue")
        })
        .unwrap_or("")
      }
      let pieces = if splitting { columns } else { 1 }
      let additions = StringBuilder()
      for part in 0..<pieces {
        let piece_span = if splitting {
          refined.search(cuts[part + 1]).unwrap() -
          refined.search(cuts[part]).unwrap()
        } else {
          span
        }
        let props = tree.split_cell_properties(
          document, cell, piece_span, merge, part, pieces,
        )
        if part == 0 {
          if properties_change(tree, document, cell, "tcPr", props)
            is Some(change) {
            changes.push(change)
          }
        } else {
          let xml = self.split_empty_cell(
            tree,
            cell,
            cuts[part + 1] - cuts[part],
            props,
          )
          guard xml.length() <= changes.limit - additions.to_string().length() else {
            @failure.reject(
              "limit-exceeded", "Split cells exceed source budget",
            )
          }
          additions.write_string(xml)
        }
      }
      if !additions.to_string().is_empty() {
        let node = tree.nodes[cell]
        changes.push({
          node: node.parent,
          offset: node.end - tree.nodes[node.parent].start,
          length: 0,
          xml: additions.to_string(),
        })
      }
    }
  }
  if extra_rows > 0 {
    let row = grid.rows[first]
    let node = tree.nodes[row]
    guard node.attributes.all(a => {
        a.uri == word_uri &&
        ["rsidR", "rsidRPr", "rsidDel", "rsidTr"].contains(a.name)
      }) &&
      tree.children[row].all(id => {
        tree.nodes[id].uri == word_uri &&
        ["trPr", "tc"].contains(tree.nodes[id].name)
      }) &&
      tree.table_children(row, "trPr").length() <= 1 else {
      @failure.reject(
        "protected-content", "Unknown row structure prevents splitting",
      )
    }
    let end = grid.model.columnSpans[first].fold(init=0, (sum, span) => {
      sum + span
    })
    let props = tree.copy_row_properties(
      document,
      row,
      after=Some(count - refined.search(positions[end]).unwrap()),
    )
    let added = StringBuilder()
    for _ in 0..<extra_rows {
      added.write_string("<od:tr xmlns:od=\"\{word_uri}\">\{props}")
      for col, cell in grid.cells[first] {
        tree.check_merge_cell(cell, self.main)
        let start = grid.starts[first][col]
        let end = start + grid.model.columnSpans[first][col]
        let span = refined.search(positions[end]).unwrap() -
          refined.search(positions[start]).unwrap()
        let pieces = if cell == target { columns } else { 1 }
        for part in 0..<pieces {
          let piece_span = if cell == target {
            refined.search(cuts[part + 1]).unwrap() -
            refined.search(cuts[part]).unwrap()
          } else {
            span
          }
          let width = if cell == target {
            cuts[part + 1] - cuts[part]
          } else {
            positions[end] - positions[start]
          }
          let properties = tree.split_cell_properties(
            document,
            cell,
            piece_span,
            if cell == target {
              ""
            } else {
              "continue"
            },
            part,
            pieces,
          )
          let xml = self.split_empty_cell(tree, cell, width, properties)
          guard xml.length() <= changes.limit - added.to_string().length() else {
            @failure.reject("limit-exceeded", "Split rows exceed source budget")
          }
          added.write_string(xml)
        }
      }
      added.write_string("</od:tr>")
    }
    changes.push({
      node: node.parent,
      offset: node.end - tree.nodes[node.parent].start,
      length: 0,
      xml: added.to_string(),
    })
  }
  self.commit_table_merge(tree, grid, changes.items, probe~, profile~, images?)
}
