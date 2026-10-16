///|
fn table_row_height_limit(
  table : @layout.Table,
  row : Int,
  page : @layout.PageSetup,
) -> Double {
  let border = table.border_width(row)
  let mut first = 0
  let mut last = 0
  while first <= row {
    last = first
    let mut r = first
    while r <= last {
      for span in table.rowSpans[r] {
        last = last.max(r + span - 1)
      }
      r += 1
    }
    if row <= last {
      break
    }
    first = last + 1
  }
  let mut available = page.height -
    page.top -
    page.bottom -
    border -
    table.border_width(last + 1)
  for r in first..<=last {
    if r != row {
      available -= table.row_minimum_height(r)
    }
  }
  ((available.max(0) * 20).floor() / 20).min(14400)
}

///|
fn Session::table_dimensions(
  self : Session,
  tree : WordTree,
  range : ParagraphRange?,
) -> Json raise @failure.Failure {
  guard range is Some(range) else { return Json::null() }
  let cell = tree.nodes[range.start.paragraph].parent
  guard tree.nodes[cell].uri == word_uri && tree.nodes[cell].name == "tc" else {
    return Json::null()
  }
  let row = tree.nodes[cell].parent
  let id = tree.nodes[row].parent
  let flow = self.flow()
  guard flow.tables.iter().find_first(t => t.id == id) is Some(table) else {
    return Json::null()
  }
  let rows = tree.table_children(id, "tr")
  guard rows.length() == table.rows.length() else { return Json::null() }
  for r, row in rows {
    if tree.table_children(row, "tc").length() != table.rows[r].length() {
      return Json::null()
    }
  }
  let index = rows.search(row).unwrap()
  let column = tree.table_children(row, "tc").search(cell).unwrap()
  let logical_column = table.columnSpans[index][:column].fold(init=0, (
    sum,
    span,
  ) => sum + span)
  let fill = table.fills[index][column]
  let border_defaults = border_defaults(tree, self.styles([]), id, [])
  {
    "id": id,
    "row": index,
    "columns": table.widths.length(),
    "column": logical_column,
    "columnWidths": table.widths,
    "width": table.widths.iter().fold(init=0.0, (sum, width) => sum + width),
    "rowHeight": table.heights[index],
    "rowHeightRule": if table.exactHeights[index] {
      "exact"
    } else {
      "atLeast"
    },
    "rows": rows.length(),
    "headerRows": table.headerRows,
    "cellVerticalAlign": table.verticalAligns[index][column],
    "cellMargins": Json(table.margins[index][column]),
    "cellBorders": cell_border_query(table, index, column),
    "tableBorders": Json::object(
      Map::from_array(
        ["top", "left", "bottom", "right", "insideH", "insideV"].map(side => {
          (side, Json(border_defaults.get(side).unwrap_or(empty_border())))
        }),
      ),
    ),
    "tableMargins": Json(table_margin_defaults(tree, self.styles([]), id, [])),
    "align": table.align,
    "cellFill": if fill.is_empty() {
      Json::null()
    } else {
      Json(fill)
    },
    "maxWidth": (flow.page.width - flow.page.left - flow.page.right).min(14400),
    "maxRowHeight": table_row_height_limit(table, index, flow.page),
  }
}

///|
fn WordTree::table_property_change(
  self : WordTree,
  document : @xml.Document,
  owner : Int,
  kind : String,
  name : String,
  attributes : Map[String, String?]?,
  markup~ : String? = None,
) -> @xml.SourceChange? raise @failure.Failure {
  let container = self.child(owner, kind)
  if container is Some(id) {
    guard self.table_children(owner, kind).length() == 1 &&
      self.nodes[id].attributes.is_empty() &&
      self.nodes[id].text.trim().is_empty() &&
      self.table_children(id, name).length() <= 1 else {
      @failure.reject(
        "protected-content", "Unknown or duplicate table properties",
      )
    }
  }
  let field = container.bind(id => self.child(id, name))
  if field is Some(id) {
    let allowed = match name {
      "trHeight" => ["val", "hRule"]
      "shd" => ["val", "color", "fill"]
      "vAlign" | "jc" | "tblHeader" => ["val"]
      "tcMar" | "tblCellMar" | "tcBorders" | "tblBorders" => []
      _ => ["w", "type"]
    }
    guard (
        self.children[id].is_empty() ||
        ["tcMar", "tblCellMar", "tcBorders", "tblBorders"].contains(name)
      ) &&
      self.nodes[id].text.trim().is_empty() &&
      self.nodes[id].attributes.all(a => {
        a.uri == word_uri && allowed.contains(a.name)
      }) else {
      @failure.reject("protected-content", "Unknown table property attributes")
    }
  }
  let markup = if markup is Some(value) {
    if field is Some(id) {
      let node = self.nodes[id]
      let source = document.source()[node.start:node.end]
      guard source == value ||
        (!source.contains("<!--") && !source.contains("<?")) else {
        @failure.reject("protected-content", "Unknown table property markup")
      }
    }
    value
  } else {
    property_markup(self, document, field, name, attributes)
  }
  if field is Some(id) {
    let node = self.nodes[id]
    return if document.source()[node.start:node.end] == markup {
      None
    } else {
      Some({ ..table_remove(self, id), xml: markup, })
    }
  }
  if markup.is_empty() {
    return None
  }
  guard container is Some(id) else {
    return properties_change(
      self,
      document,
      owner,
      kind,
      "<od:\{kind} xmlns:od=\"\{word_uri}\">\{markup}</od:\{kind}>",
    )
  }
  let node = self.nodes[id]
  let before = self.children[id]
    .iter()
    .find_first(child => {
      match name {
        "tcBorders" =>
          ["shd", "tcMar", "vAlign", "hideMark", "tcPrChange"].contains(
            self.nodes[child].name,
          )
        "tblBorders" =>
          !["tblStyle", "tblW", "jc", "tblCellSpacing", "tblInd"].contains(
            self.nodes[child].name,
          )
        "shd" => ["tcMar", "vAlign"].contains(self.nodes[child].name)
        "tcMar" => self.nodes[child].name == "vAlign"
        "vAlign" => false
        "tblHeader" =>
          ["tblCellSpacing", "jc", "hidden", "ins", "del", "trPrChange"].contains(
            self.nodes[child].name,
          )
        "jc" => !["tblStyle", "tblW"].contains(self.nodes[child].name)
        "tblCellMar" => self.nodes[child].name == "tblLook"
        _ => kind != "tblPr" || self.nodes[child].name != "tblStyle"
      }
    })
  Some(
    if node.empty {
      {
        node: id,
        offset: node.opening_end - node.start - 2,
        length: 2,
        xml: ">\{markup}</\{node.qualified}>",
      }
    } else {
      {
        node: id,
        offset: before
        .map(child => self.nodes[child].start)
        .unwrap_or(node.closing_start) -
        node.start,
        length: 0,
        xml: markup,
      }
    },
  )
}

///|
fn Session::size_table(
  self : Session,
  revision : Int,
  selection : Selection,
  value : Double,
  width~ : Bool,
  column~ : Int? = None,
  rule~ : String = "atLeast",
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  guard value >= 0 && value <= 14400 && value * 20 == (value * 20).round() else {
    @failure.reject(
      "invalid-operation", "Table sizes require nonnegative finite integer twips",
    )
  }
  let document = self.document()
  let tree = WordTree::new(document)
  let grid = self.table_grid(tree, selection)
  let body = tree.nodes[grid.table].parent
  guard tree.nodes[body].name == "body" && tree.nodes[body].uri == word_uri else {
    @failure.reject("protected-content", "Table sizes require a body table")
  }
  let flow = self.flow()
  let model = grid.model
  let changes : TableChanges = {
    items: [],
    bytes: 0,
    limit: self.opc.budget.entry_bytes.min(history_byte_limit / 2),
  }
  let twips = (value * 20).to_int()
  if width {
    guard value > 0 && model.widths.length() <= 63 else {
      @failure.reject(
        "invalid-operation", "Table width exceeds the page or column limit",
      )
    }
    let source = tree.child(grid.table, "tblGrid").unwrap()
    guard tree.table_children(grid.table, "tblGrid").length() == 1 &&
      tree.nodes[source].attributes.is_empty() &&
      tree.nodes[source].text.trim().is_empty() &&
      tree.children[source].all(id => {
        let node = tree.nodes[id]
        node.uri == word_uri &&
        node.name == "gridCol" &&
        tree.children[id].is_empty() &&
        node.text.trim().is_empty() &&
        node.attributes.all(a => a.uri == word_uri && a.name == "w")
      }) else {
      @failure.reject(
        "protected-content", "Unknown table grid prevents resizing",
      )
    }
    let widths = model.widths.map(w => (w * 20).round().to_int())
    let total = widths.iter().fold(init=0L, (sum, w) => sum + w.to_int64())
    if column is Some(column) {
      guard column >= 0 && column < widths.length() else {
        @failure.reject(
          "invalid-operation", "Column index is outside the table",
        )
      }
      widths[column] = twips
    } else {
      let mut edge = 0L
      let mut previous = 0
      for i in 0..<widths.length() {
        edge += widths[i].to_int64()
        let end = ((edge * twips.to_int64() + total / 2) / total).to_int()
        widths[i] = end - previous
        previous = end
      }
    }
    let next_total = widths.iter().fold(init=0L, (sum, w) => sum + w.to_int64())
    guard next_total.to_double() / 20 <=
      flow.page.width - flow.page.left - flow.page.right else {
      @failure.reject("invalid-operation", "Table width exceeds the page")
    }
    guard widths.all(w => w >= 240) else {
      @failure.reject(
        "invalid-operation", "Columns would be narrower than 12pt",
      )
    }
    if tree.table_property_change(
        document,
        grid.table,
        "tblPr",
        "tblW",
        Some(Map([("w", Some(next_total.to_string())), ("type", Some("dxa"))])),
      )
      is Some(change) {
      changes.push(change)
    }
    if (
        column is Some(i) &&
        (model.widths[i] * 20).round().to_int() != widths[i]
      ) ||
      (column is None && total != next_total) {
      let node = tree.nodes[source]
      let markup = document.source()[node.start:node.end]
      guard !markup.contains("<!--") && !markup.contains("<?") else {
        @failure.reject(
          "protected-content", "Unknown table grid markup prevents resizing",
        )
      }
      let markup = "<od:tblGrid xmlns:od=\"\{word_uri}\">" +
        widths.map(w => "<od:gridCol od:w=\"\{w}\"/>").join("") +
        "</od:tblGrid>"
      changes.push({ ..table_remove(tree, source), xml: markup, })
    }
    for r, row in grid.cells {
      for c, cell in row {
        tree.check_merge_cell(cell, self.main)
        let start = grid.starts[r][c]
        let width = widths[start:start + model.columnSpans[r][c]]
          .iter()
          .fold(init=0, (sum, w) => sum + w)
        guard width.to_double() / 20 >
          model.margins[r][c].left + model.margins[r][c].right else {
          @failure.reject(
            "invalid-operation", "Cell margins leave no text width",
          )
        }
        if tree.table_property_change(
            document,
            cell,
            "tcPr",
            "tcW",
            Some(Map([("w", Some(width.to_string())), ("type", Some("dxa"))])),
          )
          is Some(change) {
          changes.push(change)
        }
      }
    }
  } else {
    guard rule == "exact" ||
      value <= table_row_height_limit(model, grid.row, flow.page) else {
      @failure.reject(
        "invalid-operation", "Minimum row heights exceed one page",
      )
    }
    for cell in grid.cells[grid.row] {
      tree.check_merge_cell(cell, self.main)
    }
    guard ["atLeast", "exact"].contains(rule) else {
      @failure.reject("invalid-operation", "Unknown table row height rule")
    }
    if value != model.heights[grid.row] ||
      (rule == "exact") != model.exactHeights[grid.row] {
      let attributes = if twips == 0 && rule == "atLeast" {
        None
      } else {
        Some(Map([("val", Some(twips.to_string())), ("hRule", Some(rule))]))
      }
      if tree.table_property_change(
          document,
          grid.rows[grid.row],
          "trPr",
          "trHeight",
          attributes,
        )
        is Some(change) {
        changes.push(change)
      }
    }
  }
  if changes.items.is_empty() {
    return self.edit_state()
  }
  let (candidate, edit) = document.edit_source(changes.items)
  let updated = self.flow_from(candidate).tables
    .iter()
    .find_first(t => t.id == grid.table)
    .unwrap()
  self.check_margin_layout(updated)
  guard updated.rows.flatten().flatten().all(p => p.readOnlyReason.is_empty()) else {
    @failure.reject(
      "protected-content", "Table size requires unsupported layout",
    )
  }
  let affected = model.rows.flatten().flatten().map(p => p.id)
  let bytes = edit.payload_bytes()
  guard bytes <= history_byte_limit.to_int64() else {
    @failure.reject("limit-exceeded", "Table size history exceeds budget")
  }
  let pending = if self.selection == Some(selection) {
    self.typing_format
  } else {
    None
  }
  self.commit_edit(
    {
      xml: [edit],
      parts: Map([]),
      created: Map([]),
      before: self.selection,
      after: Some(selection.without_visual_hints()),
      paragraphs: affected,
      bytes: bytes.to_int(),
    },
    candidate,
  )
  self.typing_format = pending
  self.edit_result(affected)
}
