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
  for node in tree.nodes {
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
    if node.uri == drawing &&
      node.name == "srcRect" &&
      !node.attributes.is_empty() {
      @failure.reject(
        "unsupported-layout", "Image source cropping is unsupported",
      )
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
    height <= 14400 else {
    @failure.reject("invalid-image", "Incomplete or invalid inline image")
  }
  let rel = self.image_relationship(target)
  guard !rel.external else {
    @failure.reject(
      "missing-image", "External images require supplied resources",
    )
  }
  { key: target, width, height, }
}

///|
fn Session::image_relationship(
  self : Session,
  key : String,
) -> @opc.Relationship raise @failure.Failure {
  ignore(self.document())
  for rel in self.opc.relationships() {
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
  self.opc.read(rel.target)
}

///|
fn Session::table(
  self : Session,
  tree : WordTree,
  styles : Styles,
  id : Int,
  diagnostics : Array[String],
) -> @layout.Table raise @failure.Failure {
  let widths : Array[Double] = []
  let mut styles = styles
  if tree.child(id, "tblPr").bind(props => tree.value(props, "tblStyle"))
    is Some(key) &&
    styles.tree is Some(source) {
    for style in styles.chain(key, diagnostics) {
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
  let heights : Array[Double] = []
  let fills : Array[Array[String]] = []
  for row in tree.children[id] {
    if tree.nodes[row].name != "tr" {
      continue
    }
    let cells : Array[Array[@layout.Paragraph]] = []
    let colors : Array[String] = []
    let height = if tree.child(row, "trPr") is Some(props) {
      if tree
        .child(props, "trHeight")
        .bind(node => tree.nodes[node].attribute("hRule", uri=word_uri)) ==
        Some("exact") {
        @failure.reject(
          "unsupported-layout", "Exact table row heights are unsupported",
        )
      }
      tree
      .number(props, "trHeight", "val")
      .map(value => value / 20)
      .unwrap_or(0)
    } else {
      0
    }
    guard height >= 0 else {
      @failure.reject("invalid-table", "Negative row height")
    }
    for cell in tree.children[row] {
      if tree.nodes[cell].name != "tc" {
        continue
      }
      if tree.child(cell, "tcPr") is Some(props) &&
        (
          tree.child(props, "gridSpan") is Some(_) ||
          tree.child(props, "vMerge") is Some(_)
        ) {
        @failure.reject(
          "unsupported-layout", "Merged table cells are unsupported",
        )
      }
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
      cells.push(paragraphs)
    }
    guard !cells.is_empty() && cells.length() == widths.length() else {
      @failure.reject("invalid-table", "Table grid and cell count differ")
    }
    rows.push(cells)
    heights.push(height)
    fills.push(colors)
  }
  guard !rows.is_empty() && widths.iter().all(width => width > 6) else {
    @failure.reject("invalid-table", "Empty table or unusable grid")
  }
  let props = tree.child(id, "tblPr")
  let align = match
    props.bind(props => tree.value(props, "jc")).unwrap_or("left") {
    "start" => "left"
    "end" => "right"
    value => value
  }
  let mut borders = false
  let mut padding = 5.4
  let mut vertical_padding = 0.0
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
    if source.child(p, "tblBorders") is Some(b) {
      borders = source.children[b]
        .iter()
        .any(id => {
          source.nodes[id].attribute("val", uri=word_uri) is Some("single")
        })
      for border in source.children[b] {
        if source.nodes[border].attribute("val", uri=word_uri) is Some(value) &&
          value != "single" &&
          value != "nil" &&
          value != "none" {
          diagnostics.push("unsupported-layout:table-border-" + value)
        }
      }
      if borders {
        for edge in ["top", "left", "bottom", "right", "insideH", "insideV"] {
          guard source.child(b, edge) is Some(border) &&
            source.nodes[border].attribute("val", uri=word_uri) ==
            Some("single") else {
            @failure.reject(
              "unsupported-layout", "Only complete uniform table grids are supported",
            )
          }
          let color = source.nodes[border]
            .attribute("color", uri=word_uri)
            .unwrap_or("auto")
          guard source.nodes[border]
            .attribute("sz", uri=word_uri)
            .unwrap_or("4") ==
            "4" &&
            (color == "auto" || color == "000000") else {
            @failure.reject(
              "unsupported-layout", "Only 0.5pt black table borders are supported",
            )
          }
        }
      }
    }
    if source.child(p, "tblCellMar") is Some(margins) {
      padding = source
        .number(margins, "left", "w")
        .map(value => value / 20)
        .unwrap_or(padding)
      vertical_padding = source
        .number(margins, "top", "w")
        .map(value => value / 20)
        .unwrap_or(vertical_padding)
      guard source
        .number(margins, "right", "w")
        .map(value => value / 20)
        .unwrap_or(padding) ==
        padding &&
        source
        .number(margins, "bottom", "w")
        .map(value => value / 20)
        .unwrap_or(vertical_padding) ==
        vertical_padding else {
        @failure.reject(
          "unsupported-layout", "Asymmetric table cell margins are unsupported",
        )
      }
    }
  }
  {
    id,
    rows,
    widths,
    align,
    borders,
    padding,
    verticalPadding: vertical_padding,
    heights,
    fills,
  }
}
