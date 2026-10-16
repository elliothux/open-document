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
  let grid = self.table_grid(tree, selection)
  tree.check_table_structure(grid)
  let r = if append { grid.rows.length() - 1 } else { grid.row }
  let row = grid.rows[r]
  let before = change is RowBefore
  let removing = change is DeleteRow
  let whole = removing && grid.rows.length() == 1
  let count = grid.rows.length() + (if removing { -1 } else { 1 })
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
    for cell in grid.cells[r] {
      tree.check_merge_cell(cell, self.main)
    }
    if whole {
      tree.remove_body_table(grid.table, changes)
    } else {
      changes.push(table_remove(tree, row))
      if r + 1 < grid.rows.length() {
        for c, cell in grid.cells[r + 1] {
          let (owner, column) = grid.owners[cell]
          if owner != r {
            continue
          }
          tree.check_merge_cell(cell, self.main)
          let props = tree.split_cell_properties(
            document,
            cell,
            grid.model.columnSpans[r + 1][c],
            if grid.model.rowSpans[owner][column] > 2 {
              "restart"
            } else {
              ""
            },
            0,
            1,
          )
          if properties_change(tree, document, cell, "tcPr", props)
            is Some(change) {
            changes.push(change)
          }
        }
      }
    }
  } else {
    let position = r + (if before { 0 } else { 1 })
    let properties = tree.copy_row_properties(document, row)
    let markup = StringBuilder()
    markup.write_string("<od:tr xmlns:od=\"\{word_uri}\">\{properties}")
    let mut length = markup.to_string().length() + "</od:tr>".length()
    for c, cell in grid.cells[r] {
      tree.check_merge_cell(cell, self.main)
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
      let xml = self.split_empty_cell(tree, cell, width, props)
      guard xml.length() <= changes.limit - length else {
        @failure.reject("limit-exceeded", "Table source exceeds history budget")
      }
      length += xml.length()
      markup.write_string(xml)
    }
    markup.write_string("</od:tr>")
    let node = tree.nodes[row]
    changes.push({
      node: grid.table,
      offset: (if before { node.start } else { node.end }) -
      tree.nodes[grid.table].start,
      length: 0,
      xml: markup.to_string(),
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
  )
}
