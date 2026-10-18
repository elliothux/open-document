///|
priv struct TableCellRange {
  grid : TableGrid
  top : Int
  bottom : Int
  left : Int
  right : Int
  owners : Array[Int]
  cells : Array[Int]
  paragraphs : Array[Int]
}

///|
fn Session::table_cell_range(
  self : Session,
  tree : WordTree,
  selection : Selection,
) -> TableCellRange? raise @failure.Failure {
  if selection.anchor.paragraph == selection.focus.paragraph {
    return None
  }
  self.check_position_in(self.document(), selection.anchor)
  self.check_position_in(self.document(), selection.focus)
  let first = tree.nodes[selection.anchor.paragraph].parent
  let last = tree.nodes[selection.focus.paragraph].parent
  if first == last ||
    tree.nodes[first].name != "tc" ||
    tree.nodes[last].name != "tc" ||
    tree.nodes[first].uri != word_uri ||
    tree.nodes[last].uri != word_uri ||
    tree.nodes[tree.nodes[first].parent].parent !=
    tree.nodes[tree.nodes[last].parent].parent {
    return None
  }
  let grid = self.table_grid(tree, {
    anchor: selection.anchor,
    focus: selection.anchor,
  })
  guard grid.owners.get(last) is Some((end_row, end_column)) else {
    @failure.reject(
      "protected-content", "Selection crosses an unsupported table cell",
    )
  }
  let (start_row, start_column) = grid.owners[first]
  let top = start_row.min(end_row)
  let bottom = (start_row + grid.model.rowSpans[start_row][start_column]).max(
    end_row + grid.model.rowSpans[end_row][end_column],
  )
  let left = grid.starts[start_row][start_column].min(
    grid.starts[end_row][end_column],
  )
  let right = (grid.starts[start_row][start_column] +
  grid.model.columnSpans[start_row][start_column]).max(
    grid.starts[end_row][end_column] +
    grid.model.columnSpans[end_row][end_column],
  )
  let owners : Array[Int] = []
  let positions : Map[(Int, Int), Unit] = Map([])
  for row, cells in grid.cells {
    for column, cell in cells {
      let span = grid.model.rowSpans[row][column]
      let start = grid.starts[row][column]
      if span > 0 &&
        row < bottom &&
        row + span > top &&
        start < right &&
        start + grid.model.columnSpans[row][column] > left {
        owners.push(cell)
        positions[(row, column)] = ()
      }
    }
  }
  let cells = grid.cells
    .flatten()
    .filter(cell => positions.contains(grid.owners[cell]))
  for cell in cells {
    tree.check_merge_cell(cell, self.main)
  }
  let paragraphs = owners.map(cell => tree.table_children(cell, "p")).flatten()
  Some({ grid, top, bottom, left, right, owners, cells, paragraphs, })
}

///|
fn Session::table_cell_selection(
  self : Session,
  tree : WordTree,
  selection : Selection,
) -> Json raise @failure.Failure {
  let selected = self.table_cell_range(tree, selection)
  guard selected is Some(selected) else {
    return { "value": Json::null(), "reason": "" }
  }
  let fills : Array[Json] = []
  let alignments : Array[String] = []
  for cell in selected.owners {
    let (row, column) = selected.grid.owners[cell]
    let fill = selected.grid.model.fills[row][column]
    fills.push(if fill.is_empty() { Json::null() } else { Json(fill) })
    alignments.push(selected.grid.model.verticalAligns[row][column])
  }
  {
    "reason": "",
    "value": {
      "table": selected.grid.table,
      "top": selected.top,
      "bottom": selected.bottom,
      "left": selected.left,
      "right": selected.right,
      "count": selected.owners.length(),
      "fill": format_summary(fills, ""),
      "verticalAlign": format_summary(alignments, ""),
    },
  }
}

///|
fn Session::table_format_range(
  self : Session,
  tree : WordTree,
  selection : Selection,
) -> ParagraphRange? raise @failure.Failure {
  let first_cell = tree.nodes
    .get(selection.anchor.paragraph)
    .bind(node => tree.nodes.get(node.parent))
  let last_cell = tree.nodes
    .get(selection.focus.paragraph)
    .bind(node => tree.nodes.get(node.parent))
  // Candidate paragraph splits are validated against their supplied document below.
  guard first_cell is Some(first_cell) &&
    last_cell is Some(last_cell) &&
    first_cell.id != last_cell.id &&
    first_cell.name == "tc" &&
    last_cell.name == "tc" else {
    return None
  }
  guard self.table_cell_range(tree, selection) is Some(cells) else {
    return None
  }
  let first = cells.paragraphs[0]
  let last = cells.paragraphs.last().unwrap()
  let length = docx_texts(tree)
    .iter()
    .fold(init=0, (length, item) => {
      if item.paragraph == last {
        length + inline_text(tree.nodes[item.id]).length()
      } else {
        length
      }
    })
  Some({
    start: {
      paragraph: first,
      offset: 0,
      affinity: "after",
      bidiLevel: None,
      frameStart: None,
    },
    end: {
      paragraph: last,
      offset: length,
      affinity: "before",
      bidiLevel: None,
      frameStart: None,
    },
    paragraphs: cells.paragraphs,
  })
}

///|
/// Highlights complete selected table cells or ordinary shaped text using the same logical endpoints.
pub fn Session::selection_rects(
  self : Session,
  layout : @layout.Layout,
  selection : Selection,
) -> Array[@layout.SelectionRect] raise @failure.Failure {
  self.check_revision_value(layout.revision)
  let tree = WordTree::new(self.document())
  let selected = if self.composition is Some(_) ||
    self.picture_resize is Some(_) {
    None
  } else {
    self.table_cell_range(tree, selection) catch {
      @failure.Failure(code="protected-content", ..) => None
      error => raise error
    }
  }
  if selected is None {
    let anchor = selection.anchor
    let focus = selection.focus
    return layout.selection_rects(
      (anchor.paragraph, anchor.offset, anchor.affinity),
      (focus.paragraph, focus.offset, focus.affinity),
    )
  }
  let selected = selected.unwrap()
  let ids = Map::from_array(selected.paragraphs.map(p => (p, ())))
  let result : Array[@layout.SelectionRect] = []
  for page, frame in layout.pages {
    for area in frame.cellAreas {
      if !area.paragraphs.any(p => ids.contains(p)) {
        continue
      }
      let x = area.x.max(0)
      let y = area.y.max(0)
      let right = (area.x + area.width).min(frame.width)
      let bottom = (area.y + area.height).min(frame.height)
      if right > x && bottom > y {
        guard result.length() < 65536 else {
          @failure.reject(
            "limit-exceeded", "Cell selection geometry exceeds budget",
          )
        }
        result.push({
          page,
          line: frame.lines
          .search_by(line => area.paragraphs.contains(line.paragraph))
          .unwrap_or(0),
          x,
          y,
          width: right - x,
          height: bottom - y,
        })
      }
    }
  }
  result
}
