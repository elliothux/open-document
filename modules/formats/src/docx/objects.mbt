///|
fn Session::table(
  self : Session,
  tree : WordTree,
  styles : Styles,
  id : Int32,
  before_paragraph : Int32,
  diagnostics : Array[String],
  background~ : String,
  running~ : Bool = false,
  note_refs~ : Map[Int32, (String, String)] = Map([]),
  nesting~ : Int32 = 0,
) -> @layout.Table raise @failure.Failure {
  guard nesting <= 8 else {
    @failure.reject("limit-exceeded", "Nested table depth exceeds eight levels")
  }
  let nested_tables : Array[@layout.NestedTable] = []
  let widths : Array[Double] = []
  let (auto_fit, preferred_width) = table_sizing(tree, styles, id, diagnostics)
  let preferred_widths : Array[Array[@layout.PreferredWidth]] = []
  let mut styles = styles
  let mut default_vertical_align = "top"
  let mut default_split_row = true
  let mut default_fill = ""
  let style_margins : Array[(WordTree, Int32)] = []
  let inherited_diagnostics : Array[String] = []
  let mut default_margins = table_margin_defaults(
    tree, styles, id, inherited_diagnostics,
  )
  for item in tree.descendants(id) {
    if tree.nodes[item].name == "tblPr" ||
      tree.nodes[item].name == "trPr" ||
      tree.nodes[item].name == "tcPr" {
      tree.diagnose_properties(item, self.main, inherited_diagnostics)
    }
  }
  if tree.child(id, "tblPr").bind(props => tree.value(props, "tblStyle"))
    is Some(key) &&
    styles.tree is Some(source) {
    for style in styles.chain(key, inherited_diagnostics) {
      if source
        .child(style, "tblPr")
        .bind(p => source.table_shading(p, Some(styles.themes)))
        is Some(color) {
        default_fill = color
      }
      if source
        .child(style, "tcPr")
        .bind(p => source.table_shading(p, Some(styles.themes)))
        is Some(color) {
        default_fill = color
      }
      if source.table_row_split(style) is Some(value) {
        default_split_row = value
      }
      if source.child(style, "tcPr").bind(p => source.child(p, "tcMar"))
        is Some(id) {
        style_margins.push((source, id))
      }
      if source
        .child(style, "tcPr")
        .bind(p => source.cell_vertical_alignment(p))
        is Some(align) {
        default_vertical_align = align
      }
      if source.child(style, "pPr") is Some(p) {
        styles = {
          ..styles,
          paragraph: paragraph_properties(source, p, styles.paragraph),
        }
      }
      if source.child(style, "rPr") is Some(r) {
        styles = {
          ..styles,
          defaults: run_properties(
            source,
            r,
            styles.defaults,
            styles.themes,
            inherited=true,
          ),
        }
      }
    }
  }
  if tree
    .child(id, "tblPr")
    .bind(p => tree.table_shading(p, Some(styles.themes)))
    is Some(color) {
    default_fill = color
  }
  for (source, id) in style_margins {
    default_margins = source.table_margins(id, default_margins)
  }
  for message in inherited_diagnostics {
    if !diagnostics.contains(message) {
      diagnostics.push(message)
    }
  }
  if inherited_diagnostics.get(0) is Some(reason) {
    styles = {
      ..styles,
      paragraph: { ..styles.paragraph, readOnlyReason: reason, },
    }
  }
  if tree.child(id, "tblGrid") is Some(grid) {
    for column in tree.children[grid] {
      if tree.nodes[column].name == "gridCol" &&
        tree.nodes[column].attribute("w", uri=word_uri) is Some(width) {
        widths.push(
          (@string.parse_int(width[:]).to_double() / 20) catch {
            _ => @failure.reject("invalid-table", "Invalid grid width")
          },
        )
      }
    }
  }
  let rows : Array[Array[Array[@layout.Paragraph]]] = []
  let mut header_rows = 0
  let heights : Array[Double] = []
  let exact_heights : Array[Bool] = []
  let split_rows : Array[Bool] = []
  let fills : Array[Array[String]] = []
  let vertical_aligns : Array[Array[String]] = []
  let margins : Array[Array[@layout.CellMargins]] = []
  let column_spans : Array[Array[Int32]] = []
  let row_spans : Array[Array[Int32]] = []
  let mut previous : Map[(Int32, Int32), (Int32, Int32)] = Map([])
  for row in tree.children[id] {
    if tree.nodes[row].name != "tr" {
      continue
    }
    if rows.length() == header_rows &&
      tree.child(row, "trPr").bind(p => tree.child(p, "tblHeader"))
      is Some(flag) {
      guard tree.valid_on_off_property(flag) else {
        @failure.reject("unsupported-layout", "Invalid table header property")
      }
      if !["0", "false", "off"].contains(
          tree.nodes[flag].attribute("val", uri=word_uri).unwrap_or("1"),
        ) {
        header_rows += 1
      }
    }
    let cells : Array[Array[@layout.Paragraph]] = []
    let colors : Array[String] = []
    let alignments : Array[String] = []
    let cell_margins : Array[@layout.CellMargins] = []
    let cell_widths : Array[@layout.PreferredWidth] = []
    let spans : Array[Int32] = []
    let vertical : Array[Int32] = []
    let current : Map[(Int32, Int32), (Int32, Int32)] = Map([])
    let mut column = 0
    let (height, exact) = tree.table_row_height(row)
    exact_heights.push(exact)
    split_rows.push(tree.table_row_split(row).unwrap_or(default_split_row))
    for cell in tree.children[row] {
      if tree.nodes[cell].name != "tc" {
        continue
      }
      let props = tree.child(cell, "tcPr")
      cell_widths.push(
        props
        .bind(p => tree.child(p, "tcW"))
        .map(id => tree.preferred_table_width(id))
        .unwrap_or(@layout.PreferredWidth::new()),
      )
      let margin = if props.bind(p => tree.child(p, "tcMar")) is Some(id) {
        tree.table_margins(id, default_margins)
      } else {
        default_margins
      }
      cell_margins.push(margin)
      alignments.push(
        props
        .bind(p => tree.cell_vertical_alignment(p))
        .unwrap_or(default_vertical_align),
      )
      let span = props.bind(p => tree.number(p, "gridSpan", "val")).unwrap_or(1)
      guard span >= 1 &&
        span == span.floor() &&
        span <= widths.length().to_double() &&
        column + span.to_int() <= widths.length() else {
        @failure.reject("invalid-table", "Invalid table grid span")
      }
      let span = span.to_int()
      let width = widths[column:column + span]
        .iter()
        .fold(init=0.0, (total, width) => total + width)
      guard auto_fit || width > margin.left + margin.right else {
        @failure.reject("invalid-style", "Cell margins leave no text width")
      }
      let merge = props.bind(p => tree.child(p, "vMerge"))
      let state = merge
        .map(id => {
          tree.nodes[id].attribute("val", uri=word_uri).unwrap_or("continue")
        })
        .unwrap_or("")
      guard ["", "restart", "continue"].contains(state) else {
        @failure.reject("invalid-table", "Invalid vertical merge state")
      }
      let continued = state == "continue"
      if continued {
        guard previous.get((column, span)) is Some((r, c)) else {
          @failure.reject(
            "invalid-table", "Vertical merge has no matching start",
          )
        }
        row_spans[r][c] += 1
        current[(column, span)] = (r, c)
      } else if state == "restart" {
        current[(column, span)] = (rows.length(), cells.length())
      }
      spans.push(span)
      vertical.push(if continued { 0 } else { 1 })
      let paragraphs : Array[@layout.Paragraph] = []
      let color = props
        .bind(p => tree.table_shading(p, Some(styles.themes)))
        .unwrap_or(default_fill)
      colors.push(color)
      for item in tree.children[cell] {
        match tree.nodes[item].name {
          "p" =>
            paragraphs.push(
              self.paragraph(
                tree,
                styles,
                item,
                diagnostics,
                background=if color.is_empty() { background } else { color },
                running~,
                note_refs~,
              ),
            )
          "tcPr" => ()
          "tbl" =>
            nested_tables.push({
              row: rows.length(),
              column: cells.length(),
              table: self.table(
                tree,
                styles,
                item,
                paragraphs.length(),
                diagnostics,
                background=if color.is_empty() { background } else { color },
                running~,
                note_refs~,
                nesting=nesting + 1,
              ),
            })
          _ =>
            @failure.reject(
              "unsupported-layout", "Nested or unsupported table content",
            )
        }
      }
      if continued &&
        paragraphs.any(p => {
          p.spans.any(s => !s.text.is_empty() || s.drawing is Some(_))
        }) {
        @failure.reject(
          "unsupported-layout", "Vertical continuation contains visible content",
        )
      }
      cells.push(if continued { [] } else { paragraphs })
      column += span
    }
    guard !cells.is_empty() &&
      column + tree.row_grid_after(row) == widths.length() else {
      @failure.reject("invalid-table", "Table grid and cell count differ")
    }
    rows.push(cells)
    preferred_widths.push(cell_widths)
    heights.push(height)
    fills.push(colors)
    vertical_aligns.push(alignments)
    margins.push(cell_margins)
    column_spans.push(spans)
    row_spans.push(vertical)
    previous = current
  }
  guard !rows.is_empty() && widths.iter().all(width => width > 0) else {
    @failure.reject("invalid-table", "Empty table or unusable grid")
  }
  let props = tree.child(id, "tblPr")
  let mut align = "left"
  let borders = table_border_grid(
    tree,
    styles,
    id,
    column_spans,
    row_spans,
    widths.length(),
    diagnostics,
  )
  let properties : Array[(WordTree, Int32)] = []
  if props.bind(props => tree.value(props, "tblStyle")) is Some(key) &&
    styles.tree is Some(style_tree) {
    for style in styles.chain(key, diagnostics) {
      if style_tree.child(style, "tblPr") is Some(p) {
        properties.push((style_tree, p))
      }
    }
  }
  if props is Some(props) {
    properties.push((tree, props))
  }
  for (source, p) in properties {
    if source.value(p, "jc") is Some(value) {
      align = match value {
        "start" => "left"
        "end" => "right"
        value => value
      }
    }
  }
  for row in tree.table_children(id, "tr") {
    if tree.child(row, "trPr").bind(p => tree.value(p, "jc")) is Some(row_align) {
      let row_align = match row_align {
        "start" => "left"
        "end" => "right"
        value => value
      }
      guard row_align == align else {
        @failure.reject(
          "unsupported-layout", "Per-row table alignment requires row positioning support",
        )
      }
    }
  }
  guard ["left", "center", "right"].contains(align) else {
    @failure.reject("unsupported-layout", "Unsupported table alignment")
  }
  let mut safe_header_rows = 0
  while safe_header_rows < header_rows {
    let mut end = safe_header_rows
    let mut row = safe_header_rows
    while row <= end {
      for span in row_spans[row] {
        end = end.max(row + span - 1)
      }
      row += 1
    }
    if end >= header_rows {
      break
    }
    safe_header_rows = end + 1
  }
  {
    id,
    autoFit: auto_fit,
    preferredWidth: preferred_width,
    preferredWidths: preferred_widths,
    headerRows: safe_header_rows,
    beforeParagraph: before_paragraph,
    nestedTables: nested_tables,
    legacyCellAlignment: nesting == 0 && self.legacy_table_alignment(),
    rows,
    columnSpans: column_spans,
    rowSpans: row_spans,
    widths,
    align,
    borders,
    margins,
    heights,
    exactHeights: exact_heights,
    splitRows: split_rows,
    fills,
    verticalAligns: vertical_aligns,
  }
}
