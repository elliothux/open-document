///|
fn WordTree::is_row_revision(self : WordTree, id : Int32) -> Bool {
  guard self.nodes.get(id) is Some(node) &&
    node.uri == word_uri &&
    ["ins", "del"].contains(node.name) &&
    self.nodes.get(node.parent) is Some(properties) &&
    properties.uri == word_uri &&
    properties.name == "trPr" &&
    self.nodes.get(properties.parent) is Some(row) else {
    return false
  }
  row.uri == word_uri && row.name == "tr"
}

///|
fn WordTree::row_revision(self : WordTree, row : Int32) -> Int32? {
  self
  .child(row, "trPr")
  .bind(properties => {
    self.children[properties].iter().find_first(id => self.is_row_revision(id))
  })
}

///|
fn WordTree::check_row_revision(
  self : WordTree,
  id : Int32,
) -> Int32 raise @failure.Failure {
  guard self.is_row_revision(id) else {
    @failure.reject("protected-content", "Invalid row revision parent")
  }
  let node = self.nodes[id]
  let properties = self.nodes[node.parent]
  let row = self.nodes[properties.parent]
  let table = self.nodes[row.parent]
  let source = self.source[row.start:row.end]
  guard self.children[id].is_empty() &&
    node.text.trim().is_empty() &&
    node.attributes.all(a => {
      a.uri == word_uri && ["id", "author", "date"].contains(a.name)
    }) &&
    properties.attributes.is_empty() &&
    properties.text.trim().is_empty() &&
    self.children[properties.id].filter(id => self.is_row_revision(id)).length() ==
    1 &&
    self.children[properties.id].all(id => {
      let child = self.nodes[id]
      child.uri == word_uri &&
      (
        ["ins", "del", "trHeight", "gridAfter", "trPrChange"].contains(
          child.name,
        ) ||
        (
          ["cantSplit", "tblHeader"].contains(child.name) &&
          self.valid_on_off_property(id)
        )
      )
    }) &&
    self.table_children(row.id, "trPr").length() == 1 &&
    self.table_children(properties.id, "tblHeader").length() <= 1 &&
    row.attributes.all(a => {
      a.uri == word_uri &&
      ["rsidR", "rsidRPr", "rsidDel", "rsidTr"].contains(a.name)
    }) &&
    row.text.trim().is_empty() &&
    self.children[row.id].all(id => {
      self.nodes[id].uri == word_uri &&
      ["trPr", "tc"].contains(self.nodes[id].name)
    }) &&
    table.uri == word_uri &&
    table.name == "tbl" &&
    self.nodes[table.parent].uri == word_uri &&
    self.nodes[table.parent].name == "body" &&
    self.nodes[table.parent].parent == 0 &&
    !source.contains("<!--") &&
    !source.contains("<?") else {
    @failure.reject(
      "protected-content", "Unknown or conflicting table row revision",
    )
  }
  ignore(comment_key(node.attribute("id", uri=word_uri).unwrap_or("")))
  ignore(self.table_row_height(row.id))
  ignore(self.table_row_split(row.id))
  ignore(self.row_grid_after(row.id))
  if self.child(properties.id, "trPrChange") is Some(change) {
    ignore(self.check_row_property_revision(change))
  }
  let cells = self.table_children(row.id, "tc")
  guard !cells.is_empty() else {
    @failure.reject("protected-content", "Revision row has no cells")
  }
  for cell in cells {
    self.check_merge_cell(cell, "", notes=true, review=true)
  }
  self.child(cells[0], "p").unwrap()
}

///|
fn Session::row_revision_rects(
  self : Session,
  tree : WordTree,
  id : Int32,
  layout : @layout.Layout,
) -> Array[@layout.SelectionRect] raise @failure.Failure {
  let row = tree.nodes[tree.nodes[id].parent].parent
  let whole = tree.nodes[id].name == "tblPrChange"
  let cell = tree.nodes[id].name == "tcPrChange"
  let row = if cell { tree.nodes[row].parent } else { row }
  let table = if whole { row } else { tree.nodes[row].parent }
  let model = self.flow().tables
    .iter()
    .find_first(model => model.id == table)
    .unwrap()
  let grid = read_table_grid(
    tree,
    model,
    if whole {
      0
    } else {
      tree.table_children(table, "tr").search(row).unwrap()
    },
    if cell {
      tree
      .table_children(row, "tc")
      .search(tree.nodes[tree.nodes[id].parent].parent)
      .unwrap()
    } else {
      0
    },
  )
  let paragraphs : Set[Int32] = Set([])
  let cells = if whole {
    grid.cells.flatten()
  } else if cell {
    let owner = grid.owners[tree.nodes[tree.nodes[id].parent].parent]
    [grid.cells[owner.0][owner.1]]
  } else {
    grid.cells[grid.row]
  }
  for cell in cells {
    let (r, c) = grid.owners[cell]
    for paragraph in model.rows[r][c] {
      paragraphs.add(paragraph.id)
    }
  }
  let rects : Array[@layout.SelectionRect] = []
  for page_index, page in layout.pages {
    for area in page.cellAreas {
      if !area.paragraphs.any(id => paragraphs.contains(id)) {
        continue
      }
      let x = area.x.max(0)
      let y = area.y.max(0)
      let width = (area.x + area.width).min(page.width) - x
      let height = (area.y + area.height).min(page.height) - y
      if width <= 0 || height <= 0 {
        continue
      }
      guard rects.length() < 65536 else {
        @failure.reject(
          "limit-exceeded", "Revision rectangles exceed geometry budget",
        )
      }
      rects.push({ page: page_index, line: 0, x, y, width, height, })
    }
  }
  guard !rects.is_empty() else {
    @failure.reject(
      "protected-content", "Revision row has no current layout geometry",
    )
  }
  rects
}

///|
fn Session::resolve_row_revisions(
  self : Session,
  document : @xml.Document,
  entries : Array[RevisionEntry],
  accept : Bool,
) -> (@xml.Document, Array[@xml.Edit], Array[Int32], Int32) raise @failure.Failure {
  let initial = WordTree::new(document)
  let tables = Set::from_array(
    entries.map(entry => {
      initial.nodes[initial.nodes[initial.nodes[entry.node].parent].parent].parent
    }),
  )
  let mut candidate = document
  let steps : Array[@xml.Edit] = []
  let affected : Array[Int32] = []
  let mut bytes = 0
  for
    table in self.flow_from(document).tables.filter(model => {
      tables.contains(model.id)
    }) {
    let tree = WordTree::new(candidate)
    let model = self.flow_from(candidate).tables
      .iter()
      .find_first(model => model.id == table.id)
      .unwrap()
    let grid = read_table_grid(tree, model, 0, 0)
    tree.check_table_structure(grid, review=true)
    let changes : TableChanges = {
      items: [],
      bytes: 0,
      limit: self.opc.budget.entry_bytes.min(history_byte_limit / 2),
    }
    let marks = entries.filter(entry => {
      tree.nodes[tree.nodes[tree.nodes[entry.node].parent].parent].parent ==
      model.id
    })
    let removed = marks
      .filter(entry => (entry.kind == "rowInsert") != accept)
      .map(entry => tree.nodes[tree.nodes[entry.node].parent].parent)
    self.remove_table_rows(candidate, tree, grid, removed, changes, review=true)
    for entry in marks {
      let row = tree.nodes[tree.nodes[entry.node].parent].parent
      if !removed.contains(row) {
        changes.push(table_remove(tree, entry.node))
      }
    }
    for entry in marks {
      let row = tree.nodes[tree.nodes[entry.node].parent].parent
      affected.append(
        tree
        .descendants(row)
        .filter(id => {
          tree.nodes[id].uri == word_uri && tree.nodes[id].name == "p"
        }),
      )
    }
    let (updated, step) = candidate.edit_source(changes.items)
    let size = edit_bytes(step)
    guard size <= history_byte_limit - bytes else {
      @failure.reject("limit-exceeded", "Revision history exceeds budget")
    }
    bytes += size
    candidate = updated
    steps.push(step)
    let first = model.rows[0][0][0]
    if !first.pageBreakBefore {
      continue
    }
    let paragraph = if removed.length() == grid.rows.length() {
      let next = WordTree::new(candidate)
      let body = tree.nodes[model.id].parent
      next.children[body][tree.children[body].search(model.id).unwrap()]
    } else {
      self.flow_from(candidate).tables
      .iter()
      .find_first(table => table.id == model.id)
      .unwrap().rows[0][0][0].id
    }
    if paragraph == first.id {
      continue
    }
    let position = table_position(paragraph)
    if self.format_paragraph_document(
        candidate,
        { anchor: position, focus: position, },
        ParagraphFormat::new(pageBreakBefore=Set(true)),
      )
      is Some((updated, step)) {
      let size = edit_bytes(step)
      guard size <= history_byte_limit - bytes else {
        @failure.reject("limit-exceeded", "Revision history exceeds budget")
      }
      bytes += size
      candidate = updated
      steps.push(step)
      affected.push(paragraph)
    }
  }
  (candidate, steps, affected, bytes)
}
