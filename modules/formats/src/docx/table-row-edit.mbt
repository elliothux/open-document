///|
fn Session::edit_table_rows(
  self : Session,
  revision : Int,
  selection : Selection,
  change : TableEdit,
  append~ : Bool = false,
  probe~ : @layout.TextProbe? = None,
  profile~ : Map[String, String] = Map([]),
  images~ : @layout.Images? = None,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  guard change is RowBefore || change is RowAfter || change is DeleteRow else {
    @failure.reject("invalid-operation", "Unknown table row operation")
  }
  let document = self.document()
  let tree = WordTree::new(document)
  let selected = self.table_cell_range(tree, selection, notes=true, review=true)
  let grid = selected
    .map(range => range.grid)
    .unwrap_or_else(() => {
      self.table_grid(tree, selection, notes=true, review=true)
    })
  tree.check_table_structure(grid, review=true)
  let before = change is RowBefore
  let removing = change is DeleteRow
  let rows = if append {
    [grid.rows.last().unwrap()]
  } else {
    selected.map(range => range.source_rows()).unwrap_or([grid.rows[grid.row]])
  }
  let row = if before || removing { rows[0] } else { rows.last().unwrap() }
  let r = grid.rows.search(row).unwrap()
  let removed = if removing {
    rows.filter(row => {
      guard self.tracking_context is Some((author, _)) else {
        guard tree.row_revision(row) is None else {
          @failure.reject(
            "protected-content", "Resolve the existing row revision before deleting it",
          )
        }
        return true
      }
      guard tree.row_revision(row) is Some(mark) else { return false }
      let node = tree.nodes[mark]
      guard node.name == "ins" &&
        node.attribute("author", uri=word_uri) == Some(author) else {
        @failure.reject(
          "protected-content", "Resolve the existing row revision before deleting it",
        )
      }
      true
    })
  } else {
    []
  }
  let whole = removing && grid.rows.length() == removed.length()
  let count = grid.rows.length() +
    (if removing { -removed.length() } else { rows.length() })
  guard count <= 1000 &&
    count.to_int64() * grid.model.widths.length().to_int64() <= 4096 else {
    @failure.reject("limit-exceeded", "Table exceeds row column or cell budget")
  }
  let changes : TableChanges = {
    items: [],
    bytes: 0,
    limit: self.opc.budget.entry_bytes.min(history_byte_limit / 2),
  }
  if removing {
    self.remove_table_rows(document, tree, grid, removed, changes, review=true)
    let recorded = rows.filter(row => !removed.contains(row))
    let ids = tree.unused_revision_ids(recorded.length())
    for index, row in recorded {
      let (author, date) = self.tracking_context.unwrap()
      for cell in tree.table_children(row, "tc") {
        tree.check_merge_cell(cell, self.main, notes=true, review=true)
      }
      let markup = review_paragraph_markup(ids[index], author, date, true)
      if tree.table_property_change(
          document,
          row,
          "trPr",
          "del",
          None,
          markup=Some(markup),
        )
        is Some(change) {
        changes.push(change)
      }
    }
  } else {
    let position = r + (if before { 0 } else { 1 })
    let properties = tree.copy_row_properties(document, row, review=true)
    let markup = StringBuilder()
    markup.write_string("<od:tr xmlns:od=\"\{word_uri}\">\{properties}")
    let mut length = markup.to_string().length() + "</od:tr>".length()
    for c, cell in grid.cells[r] {
      tree.check_merge_cell(cell, self.main, notes=true, review=true)
      let (owner, column) = grid.owners[cell]
      let continued = owner < position &&
        owner + grid.model.rowSpans[owner][column] > position
      let span = grid.model.columnSpans[r][c]
      let start = grid.starts[r][c]
      let width = (grid.model.widths[start:start + span].fold(init=0.0, (
          sum,
          width,
        ) => sum + width) *
        20)
        .round()
        .to_int()
      let props = tree.split_cell_properties(
        document,
        cell,
        span,
        if continued {
          "continue"
        } else {
          ""
        },
        0,
        1,
      )
      let xml = self.split_empty_cell(tree, cell, width, props, review=true)
      guard xml.length() <= changes.limit - length else {
        @failure.reject("limit-exceeded", "Table source exceeds history budget")
      }
      length += xml.length()
      markup.write_string(xml)
    }
    markup.write_string("</od:tr>")
    let xml = markup.to_string()
    guard xml.length().to_int64() * rows.length().to_int64() <=
      changes.limit.to_int64() else {
      @failure.reject("limit-exceeded", "Table source exceeds history budget")
    }
    let xml = if self.tracking_context is Some((author, date)) {
      let ids = tree.unused_revision_ids(rows.length())
      let result = StringBuilder()
      for id in ids {
        let mark = review_paragraph_markup(id, author, date, false)
        let props = if properties.is_empty() {
          "<od:trPr>\{mark}</od:trPr>"
        } else {
          properties[:properties.length() - "</od:trPr>".length()].to_owned() +
          mark +
          "</od:trPr>"
        }
        let opening = "<od:tr xmlns:od=\"\{word_uri}\">"
        result.write_string(
          opening +
          props +
          xml[opening.length() + properties.length():].to_owned(),
        )
      }
      result.to_string()
    } else {
      xml.repeat(rows.length())
    }
    guard xml.length() <= changes.limit else {
      @failure.reject("limit-exceeded", "Table source exceeds history budget")
    }
    let node = tree.nodes[row]
    changes.push({
      node: grid.table,
      offset: (if before { node.start } else { node.end }) -
      tree.nodes[grid.table].start,
      length: 0,
      xml,
    })
  }
  self.commit_table_structure(
    tree,
    grid,
    changes.items,
    if removing {
      r.min(count - 1)
    } else {
      r + (if before { 0 } else { 1 })
    },
    0,
    whole,
    probe,
    profile,
    images,
    tracking=true,
  )
}

///|
fn Session::remove_table_rows(
  self : Session,
  document : @xml.Document,
  tree : WordTree,
  grid : TableGrid,
  rows : Array[Int],
  changes : TableChanges,
  review~ : Bool = false,
) -> Unit raise @failure.Failure {
  if rows.is_empty() {
    return
  }
  for row in rows {
    for cell in grid.cells[grid.rows.search(row).unwrap()] {
      tree.check_merge_cell(cell, self.main, notes=true, review~)
    }
  }
  if rows.length() == grid.rows.length() {
    tree.remove_body_table(grid.table, changes)
    return
  }
  for row in rows {
    changes.push(table_remove(tree, row))
  }
  for next in 0..<grid.rows.length() {
    if rows.contains(grid.rows[next]) {
      continue
    }
    for c, cell in grid.cells[next] {
      let (owner, column) = grid.owners[cell]
      if !rows.contains(grid.rows[owner]) {
        continue
      }
      let survivors = grid.rows[owner:owner + grid.model.rowSpans[owner][column]].filter(row => {
          !rows.contains(row)
        },
      )
      if survivors[0] != grid.rows[next] {
        continue
      }
      tree.check_merge_cell(cell, self.main, notes=true, review~)
      let props = tree.split_cell_properties(
        document,
        cell,
        grid.model.columnSpans[next][c],
        if survivors.length() > 1 {
          "restart"
        } else {
          ""
        },
        0,
        1,
      )
      if properties_change(tree, document, cell, "tcPr", props) is Some(change) {
        changes.push(change)
      }
    }
  }
}
