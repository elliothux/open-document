///|
fn Session::paste_table_fragment(
  self : Session,
  revision : Int,
  selection : Selection,
  fragment : String,
  probe : @layout.TextProbe?,
  profile : Map[String, String],
  images : @layout.Images?,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let parts = self.parts.copy()
  let media = self.media.copy()
  let added_media : Map[String, Bytes] = Map([])
  let part_edits : Map[String, Array[@xml.Edit]] = Map([])
  let created : Map[String, @xml.Document] = Map([])
  let (incoming, source) = self.read_table_fragment(
    fragment, parts, part_edits, created, media, added_media,
  )
  let original = self.document()
  let tree = WordTree::new(original)
  let selected = self.table_cell_range(
    tree,
    selection,
    pictures=true,
    fields=true,
  )
  let grid = selected
    .map(r => r.grid)
    .unwrap_or_else(() => self.table_grid(tree, selection, fields=true))
  let (top, c) = selected
    .map(r => grid.owners[r.owners[0]])
    .unwrap_or_else(() => grid.owners[grid.cells[grid.row][grid.column]])
  let left = grid.starts[top][c]
  let bottom = top + source.rows.length()
  let right = left + source.model.widths.length()
  let rows = bottom.max(grid.rows.length())
  let columns = right.max(grid.model.widths.length())
  guard rows <= 1000 &&
    columns <= 63 &&
    rows.to_int64() * columns.to_int64() <= 4096 else {
    @failure.reject("limit-exceeded", "Pasted rich table exceeds cell budget")
  }
  for row in top..<bottom.min(grid.rows.length()) {
    for column, cell in grid.cells[row] {
      let start = grid.starts[row][column]
      if start < right && start + grid.model.columnSpans[row][column] > left {
        tree.check_merge_cell(cell, self.main, pictures=true, fields=true)
        for id in tree.descendants(cell) {
          if tree.nodes[id].uri == word_uri && tree.nodes[id].name == "drawing" {
            ignore(self.editable_picture(tree, id, remove=true))
          }
        }
        let (r, c) = grid.owners[cell]
        guard r >= top &&
          r + grid.model.rowSpans[r][c] <= bottom &&
          grid.starts[r][c] >= left &&
          grid.starts[r][c] + grid.model.columnSpans[r][c] <= right else {
          @failure.reject(
            "protected-content", "Rich paste must cover complete destination merges",
          )
        }
        let node = tree.nodes[cell]
        let xml = original.source()[node.start:node.end]
        guard !xml.contains("<!--") &&
          !xml.contains("<?") &&
          tree
          .table_children(cell, "p")
          .all(p => {
            tree.children[p].all(id => {
              if tree.nodes[id].name == "hyperlink" {
                tree.check_hyperlink(id)
                tree.children[id].all(child => {
                  tree.nodes[child].uri == word_uri &&
                  tree.nodes[child].name == "r"
                })
              } else {
                ["pPr", "r", "fldSimple"].contains(tree.nodes[id].name)
              }
            })
          }) else {
          @failure.reject(
            "protected-content", "Rich paste cannot discard destination identity or unknown source",
          )
        }
      }
    }
  }
  let probe = probe.unwrap_or_else(() => {
    @failure.reject("missing-font", "Rich table pasting requires a text probe")
  })
  let growth = self.paste_grid_changes(
    tree, grid, rows, columns, probe, profile, images,
  )
  let mut candidate = original
  let steps : Array[@xml.Edit] = []
  let mut bytes = xml_part_edit_bytes(part_edits, created)
  for value in added_media.values() {
    guard value.length() <= history_byte_limit - bytes else {
      @failure.reject("limit-exceeded", "Copied picture history exceeds budget")
    }
    bytes += value.length()
  }
  if !growth.is_empty() {
    let (next, edit) = candidate.edit_source(growth)
    candidate = next
    guard edit_bytes(edit) <= history_byte_limit - bytes else {
      @failure.reject("limit-exceeded", "Rich paste history exceeds budget")
    }
    bytes += edit_bytes(edit)
    steps.push(edit)
  }
  let expanded_tree = WordTree::new(candidate)
  let expanded = read_table_grid(
    expanded_tree,
    self.flow_from(candidate).tables
    .iter()
    .find_first(t => t.id == grid.table)
    .unwrap(),
    top,
    c,
  )
  let source_tree = WordTree::new(incoming)
  let widths : TableChanges = {
    items: [],
    bytes: 0,
    limit: self.opc.budget.entry_bytes.min(history_byte_limit / 2),
  }
  for row, cells in source.cells {
    for column, cell in cells {
      let start = left + source.starts[row][column]
      let span = source.model.columnSpans[row][column]
      let width = (expanded.model.widths[start:start + span].fold(init=0.0, (
          sum,
          w,
        ) => sum + w) *
        20)
        .round()
        .to_int()
      let merge = source_tree
        .child(cell, "tcPr")
        .bind(p => source_tree.value(p, "vMerge"))
        .unwrap_or("")
      let markup = source_tree.merged_cell_properties(
        incoming, cell, width, span, merge,
      )
      if properties_change(source_tree, incoming, cell, "tcPr", markup)
        is Some(change) {
        widths.push(change)
      }
    }
  }
  let incoming = if widths.items.is_empty() {
    incoming
  } else {
    incoming.edit_source(widths.items).0
  }
  let source_tree = WordTree::new(incoming)
  let view = { ..self, parts, media, }
  let source = read_table_grid(
    source_tree,
    view.flow_from(incoming).tables[0],
    0,
    0,
  )
  let changes : TableChanges = {
    items: [],
    bytes: 0,
    limit: self.opc.budget.entry_bytes.min(history_byte_limit / 2),
  }
  for row, cells in source.cells {
    let targets = expanded.cells[top + row].filter(cell => {
      let index = expanded.cells[top + row].search(cell).unwrap()
      expanded.starts[top + row][index] >= left &&
      expanded.starts[top + row][index] < right
    })
    guard !targets.is_empty() else {
      @failure.reject(
        "protected-content", "Rich paste crosses missing source cells",
      )
    }
    let fragments = cells.map(cell => {
      source_tree.standalone_markup(incoming, cell)
    })
    if targets.length() == cells.length() &&
      targets
      .mapi((index, cell) => {
        let node = expanded_tree.nodes[cell]
        candidate.source()[node.start:node.end].to_owned() == fragments[index]
      })
      .all(same => same) {
      continue
    }
    let markup = fragments.join("")
    for index, cell in targets {
      let node = expanded_tree.nodes[cell]
      changes.push({
        node: node.parent,
        offset: node.start - expanded_tree.nodes[node.parent].start,
        length: node.end - node.start,
        xml: if index == 0 {
          markup
        } else {
          ""
        },
      })
    }
  }
  if !changes.items.is_empty() {
    let (next, edit) = candidate.edit_source(changes.items)
    guard edit_bytes(edit) <= history_byte_limit - bytes else {
      @failure.reject("limit-exceeded", "Rich paste history exceeds budget")
    }
    bytes += edit_bytes(edit)
    steps.push(edit)
    candidate = next
  }
  if steps.is_empty() && part_edits.is_empty() && created.is_empty() {
    return self.edit_state()
  }
  let flow = view.flow_from(candidate)
  let table = flow.tables.iter().find_first(t => t.id == grid.table).unwrap()
  self.check_table_layout(flow, table, Some(probe), profile, images)
  let current = WordTree::new(candidate)
  let fields = current.order.filter(id => {
    current.nodes[id].uri == word_uri &&
    current.nodes[id].name == "fldSimple" &&
    !tree.nodes.contains(id)
  })
  if !fields.is_empty() {
    let layout = @layout.paginate(
      probe,
      flow,
      profile,
      images.unwrap_or_else(() => @layout.Images::new()),
    )
    let changes = self.field_cache_changes(current, fields, layout)
    if !changes.is_empty() {
      let (next, edit) = candidate.edit_text(changes)
      guard edit_bytes(edit) <= history_byte_limit - bytes else {
        @failure.reject("limit-exceeded", "Rich field history exceeds budget")
      }
      bytes += edit_bytes(edit)
      steps.push(edit)
      candidate = next
    }
  }
  let final_grid = read_table_grid(current, table, top, 0)
  let first = final_grid.cells[top][final_grid.starts[top].search(left).unwrap()]
  let focus = {
    ..current.cell_contents_selection(first, docx_texts(current)).focus,
    affinity: "after",
  }
  let affected = grid.model.rows.flatten().flatten().map(p => p.id)
  affected.append(table.rows.flatten().flatten().map(p => p.id))
  self.commit_edit(
    {
      xml: steps,
      parts: part_edits,
      created,
      created_media: added_media,
      before: self.selection,
      after: Some({ anchor: focus, focus, }),
      paragraphs: affected,
      bytes,
    },
    candidate,
    parts~,
    media~,
  )
  self.edit_result(affected)
}
