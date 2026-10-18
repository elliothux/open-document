///|
fn WordTree::preferred_table_width(
  self : WordTree,
  id : Int,
  available : Double,
) -> Double raise @failure.Failure {
  let node = self.nodes[id]
  guard self.children[id].is_empty() &&
    node.text.trim().is_empty() &&
    node.attributes.all(a => a.uri == word_uri && ["type", "w"].contains(a.name)) else {
    @failure.reject("unsupported-layout", "Unknown table width properties")
  }
  let kind = node.attribute("type", uri=word_uri).unwrap_or("dxa")
  if kind == "auto" || kind == "nil" {
    return 0
  }
  let value = @string.parse_int(
    node.attribute("w", uri=word_uri).unwrap_or("0"),
  ) catch {
    _ => @failure.reject("unsupported-layout", "Invalid table width")
  }
  guard value >= 0 else {
    @failure.reject("unsupported-layout", "Invalid table width")
  }
  match kind {
    "dxa" if value <= 288000 => value.to_double() / 20
    "pct" if value <= 5000 => available * value.to_double() / 5000
    _ =>
      @failure.reject(
        "unsupported-layout", "Unsupported table width type or extent",
      )
  }
}

///|
fn table_sizing(
  tree : WordTree,
  styles : Styles,
  table : Int,
  available : Double,
  diagnostics : Array[String],
) -> (Bool, Double) raise @failure.Failure {
  let props = tree.child(table, "tblPr")
  let properties : Array[(WordTree, Int)] = []
  if props.bind(p => tree.value(p, "tblStyle")) is Some(key) &&
    styles.tree is Some(source) {
    for style in styles.chain(key, diagnostics) {
      if source.child(style, "tblPr") is Some(p) {
        properties.push((source, p))
      }
    }
  }
  if props is Some(p) {
    properties.push((tree, p))
  }
  let mut auto_fit = true
  let mut preferred = 0.0
  for (source, p) in properties {
    if source.child(p, "tblLayout") is Some(layout) {
      auto_fit = source.nodes[layout]
        .attribute("type", uri=word_uri)
        .unwrap_or("autofit") ==
        "autofit"
    }
    if source.child(p, "tblW") is Some(width) {
      preferred = source.preferred_table_width(width, available)
    }
  }
  (auto_fit, preferred)
}

///|
fn WordTree::fitted_grid_change(
  self : WordTree,
  document : @xml.Document,
  table : Int,
  widths : Array[Double],
) -> @xml.SourceChange? raise @failure.Failure {
  let grid = self.child(table, "tblGrid").unwrap()
  guard self.table_children(table, "tblGrid").length() == 1 &&
    self.nodes[grid].attributes.is_empty() &&
    self.nodes[grid].text.trim().is_empty() &&
    self.children[grid].all(id => {
      let node = self.nodes[id]
      node.uri == word_uri &&
      node.name == "gridCol" &&
      self.children[id].is_empty() &&
      node.text.trim().is_empty() &&
      node.attributes.all(a => a.uri == word_uri && a.name == "w")
    }) else {
    @failure.reject("protected-content", "Unknown table grid prevents fitting")
  }
  let values = widths.map(w => (w * 20).round().to_int())
  if self.children[grid].length() == values.length() &&
    self.children[grid]
    .mapi((i, id) => {
      self.nodes[id].attribute("w", uri=word_uri) == Some(values[i].to_string())
    })
    .all(v => v) {
    return None
  }
  let node = self.nodes[grid]
  let source = document.source()[node.start:node.end]
  guard !source.contains("<!--") && !source.contains("<?") else {
    @failure.reject(
      "protected-content", "Unknown table grid markup prevents fitting",
    )
  }
  Some({
    ..table_remove(self, grid),
    xml: "<od:tblGrid xmlns:od=\"\{word_uri}\">" +
    values.map(w => "<od:gridCol od:w=\"\{w}\"/>").join("") +
    "</od:tblGrid>",
  })
}

///|
fn Session::fit_table(
  self : Session,
  revision : Int,
  selection : Selection,
  mode : String,
  probe : @layout.TextProbe?,
  profile : Map[String, String],
  images : @layout.Images?,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  guard ["content", "page", "fixed"].contains(mode) else {
    @failure.reject("invalid-operation", "Invalid table fitting mode")
  }
  let probe = probe.unwrap_or_else(() => {
    @failure.reject("missing-font", "Table fitting requires a text probe")
  })
  let document = self.document()
  let tree = WordTree::new(document)
  let grid = self.table_grid(tree, selection)
  guard tree.nodes[tree.nodes[grid.table].parent].name == "body" else {
    @failure.reject("protected-content", "Table fitting requires a body table")
  }
  let flow = self.flow()
  let available = flow.columns.width(flow.page)
  let current = grid.model.fit_widths(probe, profile, available)
  let changes : TableChanges = {
    items: [],
    bytes: 0,
    limit: self.opc.budget.entry_bytes.min(history_byte_limit / 2),
  }
  if tree.table_property_change(
      document,
      grid.table,
      "tblPr",
      "tblLayout",
      Some(
        Map([("type", Some(if mode == "fixed" { "fixed" } else { "autofit" }))]),
      ),
    )
    is Some(change) {
    changes.push(change)
  }
  let width = if mode == "fixed" {
    (current.widths.fold(init=0.0, (sum, w) => sum + w) * 20)
    .round()
    .to_int()
    .to_string()
  } else if mode == "page" {
    "5000"
  } else {
    "0"
  }
  let kind = if mode == "fixed" {
    "dxa"
  } else if mode == "page" {
    "pct"
  } else {
    "auto"
  }
  if tree.table_property_change(
      document,
      grid.table,
      "tblPr",
      "tblW",
      Some(Map([("type", Some(kind)), ("w", Some(width))])),
    )
    is Some(change) {
    changes.push(change)
  }
  for r, row in grid.cells {
    for c, cell in row {
      tree.check_merge_cell(cell, self.main)
      let start = grid.starts[r][c]
      let width = current.widths[start:start + current.columnSpans[r][c]].fold(
        init=0.0,
        (sum, w) => sum + w,
      )
      let attributes = Map([
        ("type", Some(if mode == "fixed" { "dxa" } else { "auto" })),
        (
          "w",
          Some(
            if mode == "fixed" {
              (width * 20).round().to_int().to_string()
            } else {
              "0"
            },
          ),
        ),
      ])
      if tree.table_property_change(
          document,
          cell,
          "tcPr",
          "tcW",
          Some(attributes),
        )
        is Some(change) {
        changes.push(change)
      }
    }
  }
  let candidate = if changes.items.is_empty() {
    document
  } else {
    document.edit_source(changes.items).0
  }
  let next_flow = self.flow_from(candidate)
  let next = next_flow.tables
    .iter()
    .find_first(t => t.id == grid.table)
    .unwrap()
    .fit_widths(probe, profile, available)
  guard next.rows.flatten().flatten().all(p => p.readOnlyReason.is_empty()) else {
    @failure.reject(
      "protected-content", "Table fitting requires supported layout",
    )
  }
  self.check_margin_layout({ ..next, autoFit: false, })
  let target_flow = {
    ..next_flow,
    paragraphs: [],
    tables: [{ ..next, beforeParagraph: 0, }],
    pageBorders: @layout.PageBorders::new(),
    headers: Map([]),
    headerDistance: 0,
    footers: Map([]),
    footerDistance: 0,
    differentFirst: false,
    differentEven: false,
  }
  ignore(
    @layout.paginate(
      probe,
      target_flow,
      profile,
      images.unwrap_or_else(() => @layout.Images::new()),
    ),
  )
  if tree.fitted_grid_change(document, grid.table, next.widths) is Some(change) {
    changes.push(change)
  }
  if changes.items.is_empty() {
    return self.edit_state()
  }
  let (candidate, edit) = document.edit_source(changes.items)
  let affected = grid.model.rows.flatten().flatten().map(p => p.id)
  let bytes = edit.payload_bytes()
  guard bytes <= history_byte_limit.to_int64() else {
    @failure.reject("limit-exceeded", "Table fitting history exceeds budget")
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
      created_media: Map([]),
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
