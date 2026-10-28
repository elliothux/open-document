///|
priv struct DrawingTable {
  rtl : Bool
  widths : Array[Double]
  rows : Array[DrawingRow]
  owners : Array[Array[(Int32, Int32)]]
  style : TableStyleSettings
  styles : TableStyleBook
  fill : String
  alpha : Double
}

///|
priv struct DrawingRow {
  source : Ref
  height : Double
  cells : Array[DrawingCell]
}

///|
priv struct DrawingCell {
  row_span : Int32
  column_span : Int32
  h_merge : Bool
  v_merge : Bool
  source : Ref
  paragraphs : Array[TextParagraph]
  body : Body
  fill : String
  alpha : Double
  fill_source : (Ref, Ref?)?
  borders : Array[(String, Double, String, Double)]
  border_priorities : Array[Int32]
  border_sources : Array[(Ref, Ref?)?]
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
    source
    .child("xfrm", uri=presentation_uri)
    .map(item => {
      item.node.attributes.all(a => {
        a.uri.is_empty() && ["rot", "flipH", "flipV"].contains(a.name)
      })
    })
    .unwrap_or(false),
    "Unsupported table frame transform",
  )
  let parent = source.parent_matrix()
  let sx = (parent.a * parent.a + parent.b * parent.b).sqrt()
  let sy = (parent.c * parent.c + parent.d * parent.d).sqrt()
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
    properties.table_children(["noFill", "solidFill", "tableStyleId"])
    table_profile(
      properties.node.attributes.all(a => {
        a.uri.is_empty() &&
        [
          "firstRow", "lastRow", "firstCol", "lastCol", "bandRow", "bandCol", "rtl",
        ].contains(a.name) &&
        ["0", "false", "1", "true"].contains(a.value)
      }),
      "Unknown table style flags",
    )
  }
  let book = theme.tables.unwrap()
  let rtl = table.child("tblPr").map(p => flag(p.node, "rtl")).unwrap_or(false)
  let settings = table_style_settings(table.child("tblPr"), book)
  let style_parts = table_style_parts(book, settings.id)
  let (background, background_alpha) = fill_rgba(
    theme,
    table.child("tblPr").map(p => [p]).unwrap_or([]),
  )
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
    (widths.fold(init=0.0, (sum, width) => sum + width) - geometry.width / sx).abs() <
    0.01,
    "Table grid and frame widths differ",
  )
  let rows : Array[DrawingRow] = []
  let mut units = -1
  for row_index, node in row_nodes {
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
            ["gridSpan", "rowSpan"].contains(a.name) ||
            (
              ["hMerge", "vMerge"].contains(a.name) &&
              ["0", "false", "1", "true"].contains(a.value)
            )
          )
        }),
        "Unknown table cell attributes",
      )
      let row_span = number(node.attribute("rowSpan").unwrap_or("1"), 1, 1000).to_int()
      let column_span = number(node.attribute("gridSpan").unwrap_or("1"), 1, 63).to_int()
      let h_merge = flag(node, "hMerge")
      let v_merge = flag(node, "vMerge")
      table_profile(
        column + column_span <= widths.length(),
        "Table span exceeds its grid",
      )
      cell.table_children(["txBody", "tcPr"])
      table_profile(cell.child("txBody") is Some(_), "Missing table cell text")
      let layers = table_style_layers(
        settings,
        style_parts,
        row_index,
        column,
        row_nodes.length() - 1,
        widths.length() - 1,
      )
      let (paragraphs, body, reason) = read_text(
        theme,
        [cell],
        master,
        defaults,
        page_number,
        date_time,
        run_styles=layers.filter_map(layer => layer.text),
      )
      table_profile(
        (reason.is_empty() || reason == math_text_reason) &&
        !paragraphs.is_empty() &&
        body.fit == "none",
        if reason.is_empty() {
          "Empty table cell text body"
        } else {
          reason
        },
      )
      if !h_merge && !v_merge {
        units += paragraphs.fold(init=0, (sum, p) => {
          sum +
          p.runs.fold(init=1, (sum, run) => {
            sum +
            run.math
            .map(formula => formula.expression.linear_text().length())
            .unwrap_or(run.text.length())
          })
        })
      }
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
            ["marL", "marT", "marR", "marB", "anchor", "vert"].contains(a.name)
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
        direction: attribute("vert").unwrap_or("horz"),
        fit: "none",
      }
      table_profile(
        ["t", "ctr", "b"].contains(body.anchor),
        "Unsupported table cell anchor",
      )
      table_profile(
        ["horz", "vert", "vert270"].contains(body.direction),
        "Unsupported table cell text direction",
      )
      table_profile(
        h_merge ||
        v_merge ||
        body.left + body.right <
        widths[column:column + column_span].fold(init=0.0, (sum, width) => {
          sum + width
        }) *
        sx,
        "Table cell margins leave no text width",
      )
      let direct_fill = properties.filter(p => {
        p.child("noFill") is Some(_) || p.child("solidFill") is Some(_)
      })
      let (fill, alpha, fill_source) = if direct_fill is Some(p) {
        let (color, alpha) = fill_rgba(theme, [p])
        (color, alpha, solid_fill_source([p]).map(source => (source, None)))
      } else {
        table_style_fill(theme, layers).unwrap_or(("", 1, None))
      }
      let (borders, border_priorities, border_sources) = table_style_borders(
        theme,
        layers,
        row_index,
        column,
        row_nodes.length(),
        widths.length(),
        row_span,
        column_span,
        rtl,
      )
      for side, name in ["lnL", "lnT", "lnR", "lnB"] {
        guard properties.bind(p => p.child(name)) is Some(edge) else {
          continue
        }
        edge.table_children(["noFill", "solidFill", "prstDash"])
        table_profile(
          edge.node.attributes.all(a => a.uri.is_empty() && a.name == "w"),
          "Unsupported table cell pen",
        )
        let dash = dash_override(edge)
        if edge.node.attributes.is_empty() &&
          paint_fill(edge) is None &&
          dash is None {
          continue
        }
        let inherited = borders[side]
        let (color, opacity) = if paint_fill(edge) is Some(_) {
          fill_rgba(theme, [edge])
        } else {
          (inherited.0, inherited.3)
        }
        if paint_fill(edge) is Some(_) {
          border_sources[side] = solid_fill_source([edge]).map(fill => {
            (fill, None)
          })
        }
        borders[side] = (
          color,
          edge.node
          .attribute("w")
          .map(value => number(value, 1, 12700000) / 12700)
          .unwrap_or(if inherited.1 > 0 { inherited.1 } else { 1.0 }),
          if dash is Some(dash) {
            dash.node.attribute("val").unwrap_or("solid")
          } else {
            inherited.2
          },
          opacity,
        )
        border_priorities[side] = 100
      }
      cells.push({
        source: cell,
        paragraphs,
        body,
        fill,
        alpha,
        fill_source,
        borders,
        border_priorities,
        border_sources,
        row_span,
        column_span,
        h_merge,
        v_merge,
      })
    }
    rows.push({ source: row, height, cells, })
  }
  table_profile(
    (rows.fold(init=0.0, (sum, row) => sum + row.height) - geometry.height / sy).abs() <
    0.01,
    "Table row heights and frame differ",
  )
  let table : DrawingTable = {
    rtl,
    widths,
    rows,
    owners: table_owners(rows, widths.length()),
    style: settings,
    styles: book,
    fill: background,
    alpha: background_alpha,
  }
  let table = if sx == 1 && sy == 1 {
    table
  } else {
    table.resized(geometry.width, geometry.height) catch {
      @failure.Failure(code="invalid-transform", message~, ..) =>
        @failure.reject("unsupported-table", message)
      error => raise error
    }
  }
  for r, row in table.rows {
    for cell in row.cells {
      table_profile(
        !cell.owner() ||
        cell.body.direction == "horz" ||
        cell.body.top + cell.body.bottom < table.height(r, cell),
        "Cell margins leave no vertical text width",
      )
    }
  }
  Some(table)
}
