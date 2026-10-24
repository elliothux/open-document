///|
fn WordTree::check_table_structure(
  self : WordTree,
  grid : TableGrid,
  columns~ : Bool = false,
) -> Unit raise @failure.Failure {
  let tree = self
  let table = grid.table
  let rows = grid.rows
  let cells = grid.cells
  for id in [table, ..rows, ..cells.flatten()] {
    let allowed = match tree.nodes[id].name {
      "tbl" => ["tblPr", "tblGrid", "tr"]
      "tr" => ["trPr", "tc"]
      _ => ["tcPr", "p"]
    }
    guard tree.nodes[id].attributes
      .iter()
      .all(a => {
        a.uri == word_uri &&
        ["rsidR", "rsidRPr", "rsidDel", "rsidTr"].contains(a.name)
      }) &&
      tree.children[id]
      .iter()
      .all(child => {
        tree.nodes[child].uri == word_uri &&
        allowed.contains(tree.nodes[child].name)
      }) else {
      @failure.reject(
        "protected-content", "Unknown table structure prevents row or column edits",
      )
    }
    for name in ["tblPr", "tblGrid", "trPr", "tcPr"] {
      guard tree.table_children(id, name).length() <= 1 else {
        @failure.reject("protected-content", "Duplicate table properties")
      }
    }
  }
  let grid = tree.child(table, "tblGrid").unwrap()
  if columns {
    let node = tree.nodes[grid]
    let source = tree.source[node.start:node.end]
    guard node.text.trim().is_empty() &&
      !source.contains("<!--") &&
      !source.contains("<?") else {
      @failure.reject("protected-content", "Unknown table grid markup")
    }
  }
  for id in [grid, ..tree.children[grid]] {
    let node = tree.nodes[id]
    guard node.uri == word_uri &&
      (id == grid || (node.name == "gridCol" && tree.children[id].is_empty())) &&
      node.attributes
      .iter()
      .all(a => id != grid && a.uri == word_uri && a.name == "w") else {
      @failure.reject("protected-content", "Unknown table grid properties")
    }
  }
  for cell in cells.flatten() {
    if tree.child(cell, "tcPr") is Some(props) {
      guard tree.table_children(props, "tcW").length() <= 1 else {
        @failure.reject("protected-content", "Duplicate cell width")
      }
      if tree.child(props, "tcW") is Some(width) {
        guard tree.children[width].is_empty() &&
          tree.nodes[width].attributes
          .iter()
          .all(a => a.uri == word_uri && ["type", "w"].contains(a.name)) else {
          @failure.reject("protected-content", "Unknown cell width properties")
        }
      }
    }
  }
}

///|
fn WordTree::copy_row_properties(
  self : WordTree,
  document : @xml.Document,
  row : Int,
  after~ : Int? = None,
) -> String raise @failure.Failure {
  guard self.table_children(row, "trPr").length() <= 1 else {
    @failure.reject("protected-content", "Duplicate row properties")
  }
  ignore(self.table_row_height(row))
  ignore(self.table_row_split(row))
  ignore(self.row_grid_after(row))
  let original = self
    .child(row, "trPr")
    .map(id => {
      guard self.nodes[id].attributes.is_empty() &&
        self.nodes[id].text.trim().is_empty() &&
        self.table_children(id, "tblHeader").length() <= 1 &&
        self.children[id].all(child => {
          self.nodes[child].uri == word_uri &&
          (
            ["gridAfter", "trHeight"].contains(self.nodes[child].name) ||
            (
              ["tblHeader", "cantSplit"].contains(self.nodes[child].name) &&
              self.valid_on_off_property(child)
            )
          )
        }) else {
        @failure.reject(
          "protected-content", "Unknown row properties prevent structural editing",
        )
      }
      self.standalone_markup(document, id)
    })
    .unwrap_or("")
  guard after is Some(after) && after != self.row_grid_after(row) else {
    return original
  }
  guard !original.contains("<!--") && !original.contains("<?") else {
    @failure.reject(
      "protected-content", "Unknown row property markup prevents grid editing",
    )
  }
  let fields : Array[String] = []
  if after > 0 {
    fields.push("<od:gridAfter od:val=\"\{after}\"/>")
  }
  if self.child(row, "trPr") is Some(props) {
    for child in self.children[props] {
      if self.nodes[child].name != "gridAfter" {
        fields.push(self.standalone_markup(document, child))
      }
    }
  }
  "<od:trPr xmlns:od=\"\{word_uri}\">\{fields.join("")}</od:trPr>"
}

///|
fn WordTree::row_grid_change(
  self : WordTree,
  document : @xml.Document,
  row : Int,
  after : Int,
) -> @xml.SourceChange? raise @failure.Failure {
  if self.row_grid_after(row) == after {
    return None
  }
  self.table_property_change(
    document,
    row,
    "trPr",
    "gridAfter",
    if after == 0 {
      None
    } else {
      Some({ "val": Some(after.to_string()) })
    },
  )
}

///|
fn check_table_layout(
  flow : @layout.Flow,
  model : @layout.Table,
  probe : @layout.TextProbe?,
  profile : Map[String, String],
  images : @layout.Images?,
) -> Unit raise @failure.Failure {
  guard model.rows.flatten().flatten().all(p => p.readOnlyReason.is_empty()) else {
    @failure.reject(
      "protected-content", "Table formatting requires supported layout",
    )
  }
  if probe is Some(probe) {
    let (page, columns) = page_area_for_position(
      flow,
      table_start_position(model),
    )
    if !flow.sectionBreaks.is_empty() ||
      !columns.custom.is_empty() ||
      !flow.notes.is_empty() {
      let flow = {
        ..flow,
        tables: flow.tables.map(table => {
          if table.id == model.id {
            model
          } else {
            table
          }
        }),
      }
      let layout = @layout.paginate(
        probe,
        flow,
        profile,
        images.unwrap_or_else(() => @layout.Images::new()),
      )
      let fitted = model.fit_widths(
        probe,
        profile,
        column_width_in(flow, layout, table_start_position(model)),
      )
      check_margin_layout({ ..fitted, autoFit: false, }, page)
      return
    }
    let fitted = model.fit_widths(probe, profile, columns.width(page))
    check_margin_layout({ ..fitted, autoFit: false, }, page)
    ignore(
      @layout.paginate(
        probe,
        {
          ..flow,
          paragraphs: [],
          tables: [{ ..fitted, beforeParagraph: 0, }],
          pageBorders: @layout.PageBorders::new(),
          headers: Map([]),
          headerDistance: 0,
          footers: Map([]),
          footerDistance: 0,
          notes: [],
          differentFirst: false,
          differentEven: false,
        },
        profile,
        images.unwrap_or_else(() => @layout.Images::new()),
      ),
    )
  }
}

///|
fn table_structure_position(
  model : @layout.Table,
  row : Int,
  column : Int,
) -> Int raise @failure.Failure {
  for cell in model.rows[row][column:] {
    if cell.get(0) is Some(paragraph) {
      return paragraph.id
    }
  }
  // An inserted row may consist entirely of vertical continuations.
  let start = model.columnSpans[row][:column].fold(init=0, (sum, span) => {
    sum + span
  })
  for r in 0..<=row {
    let mut left = 0
    for c, cell in model.rows[r] {
      if left <= start &&
        start < left + model.columnSpans[r][c] &&
        r + model.rowSpans[r][c] > row {
        return cell[0].id
      }
      left += model.columnSpans[r][c]
    }
  }
  @failure.reject("invalid-table", "No surviving table selection")
}

///|
fn WordTree::remove_body_table(
  self : WordTree,
  table : Int,
  changes : TableChanges,
) -> Unit raise @failure.Failure {
  changes.push(table_remove(self, table))
  let node = self.nodes[table]
  let siblings = self.children[node.parent]
  let index = siblings.search(table).unwrap()
  if !siblings
    .get(index + 1)
    .map(id => self.nodes[id].name == "p")
    .unwrap_or(false) {
    changes.push({
      node: node.parent,
      offset: node.end - self.nodes[node.parent].start,
      length: 0,
      xml: "<od:p xmlns:od=\"\{word_uri}\"/>",
    })
  }
}

///|
fn Session::commit_table_structure(
  self : Session,
  tree : WordTree,
  grid : TableGrid,
  changes : Array[@xml.SourceChange],
  row : Int,
  column : Int,
  whole : Bool,
  probe : @layout.TextProbe?,
  profile : Map[String, String],
  images : @layout.Images?,
) -> Json raise @failure.Failure {
  let table = grid.table
  let body = tree.nodes[table].parent
  let first = grid.model.rows[0][0][0]
  let (updated, edit) = self.document().edit_source(changes)
  let mut candidate = updated
  let edits = [edit]
  let inserted = WordTree::new(candidate)
  let flow = self.flow_from(candidate)
  let changed = flow.tables.iter().find_first(t => t.id == table)
  let target = if whole {
    inserted.children[body][tree.children[body].search(table).unwrap()]
  } else {
    table_structure_position(changed.unwrap(), row, column)
  }
  let new_first = if whole { target } else { changed.unwrap().rows[0][0][0].id }
  if first.pageBreakBefore && new_first != first.id {
    for p in [new_first, first.id] {
      if !inserted.nodes.contains(p) {
        continue
      }
      let position = table_position(p)
      if self.format_paragraph_document(
          candidate,
          { anchor: position, focus: position, },
          ParagraphFormat::new(pageBreakBefore=Set(p == new_first)),
        )
        is Some((document, edit)) {
        candidate = document
        edits.push(edit)
      }
    }
  }
  let result = self.flow_from(candidate)
  let affected = grid.model.rows.flatten().flatten().map(p => p.id)
  if !whole {
    let model = result.tables.iter().find_first(t => t.id == table).unwrap()
    check_table_layout(result, model, probe, profile, images)
    affected.append(model.rows.flatten().flatten().map(p => p.id))
  }
  let position = table_position(target)
  self.check_position_in(candidate, position)
  let bytes = edits.fold(init=0L, (sum, edit) => sum + edit.payload_bytes())
  guard bytes <= history_byte_limit.to_int64() else {
    @failure.reject("limit-exceeded", "Table history exceeds budget")
  }
  affected.push(target)
  self.commit_edit(
    {
      xml: edits,
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
