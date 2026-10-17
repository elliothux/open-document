///|
fn Session::inline_image(
  self : Session,
  tree : WordTree,
  id : Int,
) -> @layout.InlineImage raise @failure.Failure {
  let wp = "http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
  let drawing = "http://schemas.openxmlformats.org/drawingml/2006/main"
  let rel_uri = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
  let mut width = None
  let mut height = None
  let mut target = None
  let mut inline = false
  let crop : Array[Double] = [0, 0, 0, 0]
  let mut seen_crop = false
  for item in tree.descendants(id) {
    let node = tree.nodes[item]
    if node.start < tree.nodes[id].start || node.end > tree.nodes[id].end {
      continue
    }
    if node.uri == wp && node.name == "anchor" {
      @failure.reject("unsupported-layout", "Floating images are unsupported")
    }
    if node.uri == wp && node.name == "inline" {
      inline = true
    }
    if node.uri == wp && node.name == "extent" {
      width = node
        .attribute("cx")
        .map(value => @string.parse_int(value[:]).to_double() / 12700) catch {
          _ => @failure.reject("invalid-image", "Invalid inline image width")
        }
      height = node
        .attribute("cy")
        .map(value => @string.parse_int(value[:]).to_double() / 12700) catch {
          _ => @failure.reject("invalid-image", "Invalid inline image height")
        }
    }
    if node.uri == drawing && node.name == "blip" {
      target = node.attribute("embed", uri=rel_uri)
    }
    if node.uri == drawing && node.name == "srcRect" {
      guard !seen_crop &&
        node.attributes.all(attr => {
          attr.uri.is_empty() && ["l", "t", "r", "b"].contains(attr.name)
        }) else {
        @failure.reject(
          "unsupported-layout", "Unknown or duplicate inline image crop",
        )
      }
      seen_crop = true
      for index, key in ["l", "t", "r", "b"] {
        let value = @string.parse_int(node.attribute(key).unwrap_or("0")[:]) catch {
          _ => @failure.reject("invalid-image", "Invalid inline image crop")
        }
        // shortcut: Source outsets need matching inline layout before accepting negative crop.
        guard value >= 0 && value < 100000 else {
          @failure.reject(
            "unsupported-layout", "Inline crop requires positive source insets",
          )
        }
        crop[index] = value.to_double() / 100000
      }
    }
    if node.uri == drawing &&
      node.name == "xfrm" &&
      (
        node.attribute("rot").unwrap_or("0") != "0" ||
        node.attribute("flipH") is Some("1" | "true") ||
        node.attribute("flipV") is Some("1" | "true")
      ) {
      @failure.reject(
        "unsupported-layout", "Rotated or flipped images are unsupported",
      )
    }
  }
  guard inline &&
    width is Some(width) &&
    height is Some(height) &&
    target is Some(target) &&
    width > 0 &&
    height > 0 &&
    width <= 14400 &&
    height <= 14400 &&
    crop[0] + crop[2] < 1 &&
    crop[1] + crop[3] < 1 else {
    @failure.reject("invalid-image", "Incomplete or invalid inline image")
  }
  let rel = self.image_relationship(target)
  guard width / (1 - crop[0] - crop[2]) <= 1000000000 &&
    height / (1 - crop[1] - crop[3]) <= 1000000000 else {
    @failure.reject(
      "limit-exceeded", "Expanded picture exceeds drawing coordinate budget",
    )
  }
  guard !rel.external else {
    @failure.reject(
      "missing-image", "External images require supplied resources",
    )
  }
  { key: target, width, height, crop, }
}

///|
fn Session::image_relationship(
  self : Session,
  key : String,
) -> @opc.Relationship raise @failure.Failure {
  ignore(self.document())
  for rel in self.relationships() {
    if rel.owner == self.main &&
      rel.id == key &&
      rel.kind ==
      "http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" {
      return rel
    }
  }
  @failure.reject("missing-image", "Unresolved image relationship: " + key)
}

///|
pub fn Session::image_bytes(
  self : Session,
  key : String,
) -> Bytes raise @failure.Failure {
  let rel = self.image_relationship(key)
  guard !rel.external else {
    @failure.reject(
      "missing-image", "External image bytes must be supplied explicitly",
    )
  }
  self.media.get(rel.target).unwrap_or_else(() => self.opc.read(rel.target))
}

///|
fn Session::table(
  self : Session,
  tree : WordTree,
  styles : Styles,
  id : Int,
  before_paragraph : Int,
  diagnostics : Array[String],
  available : Double,
) -> @layout.Table raise @failure.Failure {
  let widths : Array[Double] = []
  let (auto_fit, preferred_width) = table_sizing(
    tree, styles, id, available, diagnostics,
  )
  let preferred_widths : Array[Array[Double]] = []
  let mut styles = styles
  let mut default_vertical_align = "top"
  let mut default_split_row = true
  let style_margins : Array[(WordTree, Int)] = []
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
  let column_spans : Array[Array[Int]] = []
  let row_spans : Array[Array[Int]] = []
  let mut previous : Map[(Int, Int), (Int, Int)] = Map([])
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
    let cell_widths : Array[Double] = []
    let spans : Array[Int] = []
    let vertical : Array[Int] = []
    let current : Map[(Int, Int), (Int, Int)] = Map([])
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
        .map(id => tree.preferred_table_width(id, available))
        .unwrap_or(0),
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
      let color = tree
        .child(cell, "tcPr")
        .bind(props => tree.child(props, "shd"))
        .bind(shd => tree.nodes[shd].attribute("fill", uri=word_uri))
        .unwrap_or("")
      let color = if color == "auto" { "" } else { color }
      guard color.is_empty() ||
        (color.length() == 6 && color.iter().all(ch => ch.is_ascii_hexdigit())) else {
        @failure.reject("invalid-table", "Invalid cell fill color")
      }
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
                background=if color.is_empty() { "ffffff" } else { color },
              ),
            )
          "tcPr" => ()
          _ =>
            @failure.reject(
              "unsupported-layout", "Nested or unsupported table content",
            )
        }
      }
      if continued &&
        paragraphs.any(p => {
          p.spans.any(s => !s.text.is_empty() || s.image is Some(_))
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
  let properties : Array[(WordTree, Int)] = []
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
