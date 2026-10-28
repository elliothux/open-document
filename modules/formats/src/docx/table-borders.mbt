///|
fn empty_border() -> @layout.BorderStyle {
  { style: "single", width: 0, color: "000000", }
}

///|
fn WordTree::read_borders(
  self : WordTree,
  properties : Int32,
  name : String,
  themes : Map[String, String]?,
) -> Map[String, @layout.BorderStyle] raise @failure.Failure {
  let result : Map[String, @layout.BorderStyle] = Map([])
  let sources = self.table_children(properties, name)
  guard sources.length() <= 1 else {
    @failure.reject("unsupported-layout", "Duplicate border properties")
  }
  for source in sources {
    guard self.nodes[source].attributes.is_empty() &&
      self.nodes[source].text.trim().is_empty() else {
      @failure.reject("unsupported-layout", "Unknown border properties")
    }
    for id in self.children[source] {
      let node = self.nodes[id]
      let key = match node.name {
        "start" => "left"
        "end" => "right"
        value => value
      }
      guard node.uri == word_uri &&
        ["top", "left", "bottom", "right", "insideH", "insideV"].contains(key) &&
        !result.contains(key) &&
        self.children[id].is_empty() &&
        node.text.trim().is_empty() &&
        node.attributes.all(a => {
          a.uri == word_uri &&
          [
            "val", "sz", "color", "themeColor", "themeShade", "themeTint", "space",
            "shadow", "frame",
          ].contains(a.name)
        }) &&
        node.attribute("space", uri=word_uri).unwrap_or("0") == "0" &&
        ["0", "false", "off"].contains(
          node.attribute("shadow", uri=word_uri).unwrap_or("0"),
        ) &&
        ["0", "false", "off"].contains(
          node.attribute("frame", uri=word_uri).unwrap_or("0"),
        ) else {
        @failure.reject("unsupported-layout", "Unsupported border markup")
      }
      let kind = node.attribute("val", uri=word_uri).unwrap_or("none")
      guard [
        "single", "double", "dashed", "dotted", "dashSmallGap", "dotDash", "dotDotDash",
        "nil", "none",
      ].contains(kind) else {
        @failure.reject(
          "unsupported-layout", "Unsupported table border line style",
        )
      }
      let width = if !["nil", "none"].contains(kind) {
        self.number(source, node.name, "sz").unwrap_or(4) / 8
      } else {
        0.0
      }
      let fallback = node.attribute("color", uri=word_uri).unwrap_or("auto")
      // Structural guards validate the source without needing a document theme.
      let color = match themes {
        Some(values) => theme_node_color(node, fallback, values)
        None => {
          ignore(theme_color_reference(node))
          fallback
        }
      }
      let color = color.to_lower()
      let color = if color == "auto" { "000000" } else { color }
      guard width >= (if !["nil", "none"].contains(kind) { 0.25 } else { 0.0 }) &&
        width <= 12 &&
        width * 8 == (width * 8).round() &&
        color.length() == 6 &&
        color.iter().all(c => c.is_ascii_hexdigit()) else {
        @failure.reject("invalid-table", "Invalid table border width or color")
      }
      result[key] = {
        style: if width == 0 {
          "single"
        } else {
          kind
        },
        width,
        color,
      }
    }
  }
  result
}

///|
fn border_defaults(
  tree : WordTree,
  styles : Styles,
  table : Int32,
  diagnostics : Array[String],
  cells~ : Bool = false,
) -> Map[String, @layout.BorderStyle] raise @failure.Failure {
  let result : Map[String, @layout.BorderStyle] = Map([])
  if tree.child(table, "tblPr").bind(p => tree.value(p, "tblStyle"))
    is Some(key) &&
    styles.tree is Some(source) {
    for style in styles.chain(key, diagnostics) {
      if source.child(style, if cells { "tcPr" } else { "tblPr" })
        is Some(props) {
        for
          key, value in source.read_borders(
            props,
            if cells {
              "tcBorders"
            } else {
              "tblBorders"
            },
            Some(styles.themes),
          ) {
          result[key] = value
        }
      }
    }
  }
  if !cells && tree.child(table, "tblPr") is Some(props) {
    for
      key, value in tree.read_borders(props, "tblBorders", Some(styles.themes)) {
      result[key] = value
    }
  }
  result
}

///|
fn border_conflict(
  a : @layout.BorderStyle?,
  b : @layout.BorderStyle?,
) -> @layout.BorderStyle? {
  guard a is Some(a) else { return b }
  guard b is Some(b) else { return Some(a) }
  if a.extent() != b.extent() {
    return Some(if a.extent() > b.extent() { a } else { b })
  }
  if (a.style == "double") != (b.style == "double") {
    return Some(if a.style == "double" { b } else { a })
  }
  fn channels(value : String) -> (Int32, Int32, Int32) {
    fn digit(value : UInt16) -> Int32 {
      let value = value.to_int()
      if value <= 57 {
        value - 48
      } else {
        value - 87
      }
    }
    let r = digit(value[0]) * 16 + digit(value[1])
    let g = digit(value[2]) * 16 + digit(value[3])
    let b = digit(value[4]) * 16 + digit(value[5])
    (r + b + 2 * g, b + 2 * g, g)
  }
  // Equal-width single strokes precede doubles; retain ONLYOFFICE's RGB tie break.
  Some(if channels(a.color) <= channels(b.color) { a } else { b })
}

///|
fn table_border_grid(
  tree : WordTree,
  styles : Styles,
  table : Int32,
  spans : Array[Array[Int32]],
  row_spans : Array[Array[Int32]],
  columns : Int32,
  diagnostics : Array[String],
) -> @layout.TableBorders raise @failure.Failure {
  guard spans.length() <= 1000 && columns <= 63 else {
    @failure.reject(
      "limit-exceeded", "Table border grid exceeds row or column limit",
    )
  }
  let defaults = border_defaults(tree, styles, table, diagnostics)
  let cell_defaults = border_defaults(
    tree,
    styles,
    table,
    diagnostics,
    cells=true,
  )
  let horizontal : Array[Array[@layout.BorderStyle?]] = Array::makei(
    spans.length() + 1,
    _ => Array::make(columns, None),
  )
  let vertical : Array[Array[@layout.BorderStyle?]] = Array::makei(
    spans.length(),
    _ => Array::make(columns + 1, None),
  )
  let owners = Array::makei(spans.length(), _ => Array::make(columns, -1))
  let mut identity = 0
  for r, row in tree.table_children(table, "tr") {
    let mut column = 0
    for c, cell in tree.table_children(row, "tc") {
      let span = spans[r][c]
      let count = row_spans[r][c]
      if count > 0 {
        for y in r..<(r + count) {
          for x in column..<(column + span) {
            owners[y][x] = identity
          }
        }
        identity += 1
      }
      let values = cell_defaults.copy()
      if tree.child(cell, "tcPr") is Some(props) {
        for
          key, value in tree.read_borders(
            props,
            "tcBorders",
            Some(styles.themes),
          ) {
          values[key] = value
        }
      }
      for x in column..<(column + span) {
        horizontal[r][x] = border_conflict(horizontal[r][x], values.get("top"))
        let bottom = r + count.max(1)
        horizontal[bottom][x] = border_conflict(
          horizontal[bottom][x],
          values.get("bottom"),
        )
      }
      for y in r..<(r + count.max(1)) {
        vertical[y][column] = border_conflict(
          vertical[y][column],
          values.get("left"),
        )
        vertical[y][column + span] = border_conflict(
          vertical[y][column + span],
          values.get("right"),
        )
      }
      column += span
    }
  }
  {
    horizontal: horizontal.mapi((r, row) => {
      row.mapi((c, edge) => {
        let above = if r > 0 { owners[r - 1][c] } else { -1 }
        let below = if r < spans.length() { owners[r][c] } else { -1 }
        if above == below {
          empty_border()
        } else {
          edge.unwrap_or_else(() => {
            defaults
            .get(
              if above < 0 {
                "top"
              } else if below < 0 {
                "bottom"
              } else {
                "insideH"
              },
            )
            .unwrap_or(empty_border())
          })
        }
      })
    }),
    vertical: vertical.mapi((r, row) => {
      row.mapi((c, edge) => {
        let left = if c > 0 { owners[r][c - 1] } else { -1 }
        let right = if c < columns { owners[r][c] } else { -1 }
        if left == right {
          empty_border()
        } else {
          edge.unwrap_or_else(() => {
            defaults
            .get(
              if left < 0 {
                "left"
              } else if right < 0 {
                "right"
              } else {
                "insideV"
              },
            )
            .unwrap_or(empty_border())
          })
        }
      })
    }),
  }
}
