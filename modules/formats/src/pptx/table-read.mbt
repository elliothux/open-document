///|
priv struct DrawingTable {
  widths : Array[Double]
  rows : Array[DrawingRow]
}

///|
priv struct DrawingRow {
  source : Ref
  height : Double
  cells : Array[DrawingCell]
}

///|
priv struct DrawingCell {
  source : Ref
  paragraphs : Array[TextParagraph]
  body : Body
  fill : String
  alpha : Double
  borders : Array[(String, Double)]
}

///|
fn table_profile(
  condition : Bool,
  message : String,
) -> Unit raise @failure.Failure {
  guard condition else { @failure.reject("unsupported-table", message) }
}

///|
fn Ref::table_children(
  self : Ref,
  allowed : Array[String],
) -> Unit raise @failure.Failure {
  table_profile(
    self.tree.children
    .get(self.node.id)
    .unwrap_or([])
    .all(node => node.uri == drawing_uri && allowed.contains(node.name)),
    "Unsupported table content: " + self.node.name,
  )
}

///|
fn read_drawing_table(
  source : Ref,
  theme : Theme,
  master : Tree,
  defaults : Ref?,
  geometry : Geometry,
  page_number : String,
  date_time : DateTime?,
) -> DrawingTable? raise @failure.Failure {
  table_profile(
    source.parent_group().is_empty(),
    "Grouped tables require table scaling support",
  )
  table_profile(
    source
    .child("xfrm", uri=presentation_uri)
    .map(item => item.node.attributes.is_empty())
    .unwrap_or(false),
    "Unsupported table frame transform",
  )
  let data = source.child("graphic").unwrap().child("graphicData").unwrap()
  table_profile(
    data.node.attribute("uri") ==
    Some("http://schemas.openxmlformats.org/drawingml/2006/table"),
    "Unknown table graphic data",
  )
  data.table_children(["tbl"])
  let table = data.child("tbl").unwrap()
  table.table_children(["tblPr", "tblGrid", "tr"])
  if table.child("tblPr") is Some(properties) {
    properties.table_children(["noFill", "solidFill"])
    table_profile(
      properties.node.attributes.all(a => {
        a.uri.is_empty() &&
        ["firstRow", "lastRow", "firstCol", "lastCol", "bandRow", "bandCol"].contains(
          a.name,
        ) &&
        ["0", "false"].contains(a.value)
      }),
      "Table styles require table style resolution",
    )
  }
  let grid = table
    .child("tblGrid")
    .unwrap_or_error(
      @failure.Failure(
        code="malformed-pptx",
        part=source.tree.part,
        offset=-1,
        message="Missing table grid",
      ),
    )
  grid.table_children(["gridCol"])
  let widths = grid.tree
    .all(grid.node.id, "gridCol")
    .map(node => number(node.attribute("w").unwrap_or(""), 1, 182880000) / 12700)
  let row_nodes = table.tree.all(table.node.id, "tr")
  guard !widths.is_empty() &&
    widths.length() <= 63 &&
    !row_nodes.is_empty() &&
    row_nodes.length() <= 1000 &&
    widths.length().to_int64() * row_nodes.length().to_int64() <= 4096 else {
    @failure.reject("limit-exceeded", "Table dimensions exceed budget")
  }
  table_profile(
    (widths.fold(init=0.0, (sum, width) => sum + width) - geometry.width).abs() <
    0.01,
    "Table grid and frame widths differ",
  )
  let rows : Array[DrawingRow] = []
  let mut units = -1
  for node in row_nodes {
    let row : Ref = { tree: source.tree, node, }
    row.table_children(["tc"])
    table_profile(
      node.attributes.all(a => a.uri.is_empty() && a.name == "h"),
      "Unknown table row attributes",
    )
    let height = number(node.attribute("h").unwrap_or(""), 1, 182880000) / 12700
    let nodes = row.tree.all(row.node.id, "tc")
    table_profile(
      nodes.length() == widths.length(),
      "Table rows require complete cell grids",
    )
    let cells : Array[DrawingCell] = []
    for column, node in nodes {
      let cell : Ref = { tree: source.tree, node, }
      table_profile(
        node.attributes.all(a => {
          a.uri.is_empty() &&
          (
            (["gridSpan", "rowSpan"].contains(a.name) && a.value == "1") ||
            (
              ["hMerge", "vMerge"].contains(a.name) &&
              ["0", "false"].contains(a.value)
            )
          )
        }),
        "Merged table cells require span support",
      )
      cell.table_children(["txBody", "tcPr"])
      table_profile(cell.child("txBody") is Some(_), "Missing table cell text")
      let (paragraphs, body, reason) = read_text(
        theme,
        [cell],
        master,
        defaults,
        page_number,
        date_time,
      )
      table_profile(
        reason.is_empty() && !paragraphs.is_empty() && body.fit == "none",
        if reason.is_empty() {
          "Empty table cell text body"
        } else {
          reason
        },
      )
      units += paragraphs.fold(init=0, (sum, p) => {
        sum + p.runs.fold(init=1, (sum, run) => sum + run.text.length())
      })
      guard units <= 32767 else {
        @failure.reject("limit-exceeded", "Table text exceeds budget")
      }
      let properties = cell.child("tcPr")
      if properties is Some(properties) {
        properties.table_children([
          "noFill", "solidFill", "lnL", "lnT", "lnR", "lnB",
        ])
        table_profile(
          properties.node.attributes.all(a => {
            a.uri.is_empty() &&
            ["marL", "marT", "marR", "marB", "anchor"].contains(a.name)
          }),
          "Unknown table cell properties",
        )
      }
      let attribute = (name : String) => {
        properties.bind(p => p.node.attribute(name))
      }
      let body = {
        ..body,
        left: attribute("marL")
        .map(v => number(v, 0, 182880000) / 12700)
        .unwrap_or(body.left),
        top: attribute("marT")
        .map(v => number(v, 0, 182880000) / 12700)
        .unwrap_or(body.top),
        right: attribute("marR")
        .map(v => number(v, 0, 182880000) / 12700)
        .unwrap_or(body.right),
        bottom: attribute("marB")
        .map(v => number(v, 0, 182880000) / 12700)
        .unwrap_or(body.bottom),
        anchor: attribute("anchor").unwrap_or(body.anchor),
        fit: "none",
      }
      table_profile(
        ["t", "ctr", "b"].contains(body.anchor),
        "Unsupported table cell anchor",
      )
      table_profile(
        body.left + body.right < widths[column],
        "Table cell margins leave no text width",
      )
      let fills = properties.map(p => [p]).unwrap_or([])
      if table.child("tblPr") is Some(p) {
        fills.push(p)
      }
      let (fill, alpha) = fill_rgba(theme, fills)
      let borders = ["lnL", "lnT", "lnR", "lnB"].map(name => {
        guard properties.bind(p => p.child(name)) is Some(edge) else {
          return ("", 0.0)
        }
        edge.table_children(["noFill", "solidFill"])
        table_profile(
          edge.node.attributes.all(a => a.uri.is_empty() && a.name == "w"),
          "Unsupported table cell pen",
        )
        let (color, opacity) = fill_rgba(theme, [edge])
        table_profile(
          opacity == 1,
          "Transparent table cell borders require conflict resolution",
        )
        (
          color,
          number(edge.node.attribute("w").unwrap_or("12700"), 1, 12700000) /
          12700,
        )
      })
      cells.push({ source: cell, paragraphs, body, fill, alpha, borders, })
    }
    rows.push({ source: row, height, cells, })
  }
  table_profile(
    (rows.fold(init=0.0, (sum, row) => sum + row.height) - geometry.height).abs() <
    0.01,
    "Table row heights and frame differ",
  )
  Some({ widths, rows, })
}
