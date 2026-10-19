///|
fn fragment_paragraph(
  tree : WordTree,
  paragraph : @layout.Paragraph,
  styles : Styles,
  document : @xml.Document,
  limit : Int,
) -> String raise @failure.Failure {
  guard paragraph.readOnlyReason.is_empty() &&
    paragraph.marker is None &&
    tree.children[paragraph.id].all(id => {
      tree.nodes[id].uri == word_uri &&
      ["pPr", "r"].contains(tree.nodes[id].name)
    }) else {
    @failure.reject(
      "protected-content", "Rich cell fragments require ordinary paragraphs without linked resources or lists",
    )
  }
  let patch = ParagraphFormat::new(
    style=Clear,
    align=Set(paragraph.align),
    rtl=Set(paragraph.rtl),
    before=Set(paragraph.before),
    after=Set(paragraph.after),
    left=Set(paragraph.left),
    right=Set(paragraph.right),
    first=Set(paragraph.first),
    line=Set(paragraph.line),
    pageBreakBefore=Set(paragraph.pageBreakBefore),
    keepLines=Set(paragraph.keepLines),
    keepNext=Set(paragraph.keepNext),
    widowControl=Set(paragraph.widowControl),
  ).properties()
  patch["outlineLvl"] = Some(
    Map([
      (
        "val",
        Some(styles.outline_level(tree, paragraph.id).unwrap_or(9).to_string()),
      ),
    ]),
  )
  let nested = Map([
    ("rPr", ""),
    (
      "numPr",
      "<od:numPr xmlns:od=\"\{word_uri}\"><od:numId od:val=\"0\"/></od:numPr>",
    ),
    ("tabs", tabs_markup([], paragraph.tabs)),
  ])
  let props = formatted_properties(
    tree,
    document,
    paragraph.id,
    "pPr",
    patch,
    nested~,
  )
  let output = StringBuilder()
  output.write_string("<od:p>" + props)
  let mut units = props.length() + 15
  for span in paragraph.spans {
    guard span.image is None && span.field.is_empty() else {
      @failure.reject(
        "protected-content", "Rich cell fragments require owned image and field transfer",
      )
    }
    let run = if span.node == paragraph.id {
      match tree.paragraph_runs(paragraph.id).get(0) {
        Some(run) => Some(run)
        None => tree.child(paragraph.id, "pPr")
      }
    } else {
      Some(tree.nodes[span.node].parent)
    }
    if run is Some(run) && tree.nodes[run].name == "r" {
      guard tree.children[run].all(id => {
        let node = tree.nodes[id]
        node.uri == word_uri &&
        ["rPr", "t", "tab", "br", "cr"].contains(node.name) &&
        (
          node.name != "br" ||
          node.attribute("type", uri=word_uri).unwrap_or("textWrapping") ==
          "textWrapping"
        )
      }) else {
        @failure.reject(
          "protected-content", "Rich cell fragments require ordinary text runs",
        )
      }
    }
    let style = styles.character_style(tree, paragraph.id, run, [])
    let text = span.text.replace_all(old="\n", new="\u2028")
    for (style, text) in style.font_runs(text, styles.themes) {
      let format = CharacterFormat::new(
        style=Clear,
        family=Set(style.family),
        size=Set(style.size),
        color=Set(style.color),
        bold=Set(style.bold),
        italic=Set(style.italic),
        underline=Set(style.underline),
        strike=Set(style.strike),
        highlight=Set(style.highlight),
        vertAlign=Set(style.vertAlign),
      )
      format.validate()
      let properties = formatted_properties(
        tree,
        document,
        run.unwrap_or(paragraph.id),
        "rPr",
        format.properties(),
      )
      let xml = "<od:r>" + properties + inline_markup(text, limit) + "</od:r>"
      guard xml.length() <= limit - units else {
        @failure.reject(
          "limit-exceeded", "Rich cell paragraph exceeds source budget",
        )
      }
      units += xml.length()
      output.write_string(xml)
    }
  }
  output.write_string("</od:p>")
  output.to_string()
}

///|
fn Session::fragment_cell(
  self : Session,
  tree : WordTree,
  grid : TableGrid,
  row : Int,
  column : Int,
  styles : Styles,
  limit : Int,
) -> String raise @failure.Failure {
  let cell = grid.cells[row][column]
  tree.check_merge_cell(cell, self.main)
  let span = grid.model.columnSpans[row][column]
  let start = grid.starts[row][column]
  let width = grid.model.widths[start:start + span].fold(init=0.0, (sum, w) => {
    sum + w
  })
  let output = StringBuilder()
  output.write_string("<od:tc")
  let bindings = tree.namespace_bindings(cell)
  bindings["od"] = word_uri
  for prefix, uri in bindings {
    output.write_string(
      " \{if prefix.is_empty(){"xmlns"}else{"xmlns:"+prefix}}=\"\{property_attribute(uri)}\"",
    )
  }
  output.write_string(
    "><od:tcPr><od:tcW od:type=\"dxa\" od:w=\"\{(width*20).round().to_int()}\"/>",
  )
  if span > 1 {
    output.write_string("<od:gridSpan od:val=\"\{span}\"/>")
  }
  let rows = grid.model.rowSpans[row][column]
  if rows != 1 {
    output.write_string(
      "<od:vMerge od:val=\"\{if rows==0 {"continue"}else{"restart"}}\"/>",
    )
  }
  output.write_string("<od:tcBorders>")
  let borders = cell_border_query(grid.model, row, column)
  for side in ["top", "left", "bottom", "right"] {
    guard borders[side]
      is { "width": Number(width, ..), "color": String(color), .. } else {
      @failure.reject(
        "protected-content", "Rich cell fragments require uniform merged-cell edges",
      )
    }
    output.write_string(
      "<od:\{side} od:val=\"\{if width==0 {"nil"}else{"single"}}\" od:sz=\"\{(width*8).round().to_int()}\" od:color=\"\{color}\"/>",
    )
  }
  let fill = grid.model.fills[row][column]
  output.write_string(
    "</od:tcBorders><od:shd od:val=\"clear\" od:fill=\"\{if fill.is_empty(){"auto"}else{fill}}\"/><od:tcMar>",
  )
  let margin = grid.model.margins[row][column]
  for
    (side, value) in [
      ("top", margin.top),
      ("left", margin.left),
      ("bottom", margin.bottom),
      ("right", margin.right),
    ] {
    output.write_string(
      "<od:\{side} od:type=\"dxa\" od:w=\"\{(value*20).round().to_int()}\"/>",
    )
  }
  output.write_string(
    "</od:tcMar><od:vAlign od:val=\"\{grid.model.verticalAligns[row][column]}\"/></od:tcPr>",
  )
  let mut units = output.to_string().length() + 8
  let paragraphs = if rows == 0 {
    tree.table_children(cell, "p").map(p => self.paragraph(tree, styles, p, []))
  } else {
    grid.model.rows[row][column]
  }
  for paragraph in paragraphs {
    let xml = fragment_paragraph(
      tree,
      paragraph,
      styles,
      self.document(),
      limit,
    )
    guard xml.length() <= limit - units else {
      @failure.reject(
        "limit-exceeded", "Rich cell fragment exceeds source budget",
      )
    }
    units += xml.length()
    output.write_string(xml)
  }
  output.write_string("</od:tc>")
  output.to_string()
}

///|
fn Session::capture_table_fragment(
  self : Session,
  tree : WordTree,
  grid : TableGrid,
  top : Int,
  bottom : Int,
  left : Int,
  right : Int,
  owners : Array[Int],
) -> String raise @failure.Failure {
  let limit = self.opc.budget.entry_bytes.min(history_byte_limit / 2)
  let output = StringBuilder()
  output.write_string(
    "<od:tbl xmlns:od=\"\{word_uri}\"><od:tblPr><od:tblLayout od:type=\"fixed\"/></od:tblPr><od:tblGrid>",
  )
  for width in grid.model.widths[left:right] {
    output.write_string("<od:gridCol od:w=\"\{(width*20).round().to_int()}\"/>")
  }
  output.write_string("</od:tblGrid>")
  let styles = self.styles([])
  let mut units = output.to_string().length() + 10
  for row in top..<bottom {
    output.write_string("<od:tr>")
    units += 17
    for column, cell in grid.cells[row] {
      let start = grid.starts[row][column]
      if start < right && start + grid.model.columnSpans[row][column] > left {
        let (owner_row, owner_column) = grid.owners[cell]
        guard owners.contains(grid.cells[owner_row][owner_column]) else {
          @failure.reject(
            "protected-content", "Rich cell copy requires a fully selected rectangle",
          )
        }
        guard start >= left &&
          start + grid.model.columnSpans[row][column] <= right &&
          owner_row >= top &&
          owner_row + grid.model.rowSpans[owner_row][owner_column] <= bottom else {
          @failure.reject(
            "protected-content", "Rich cell copy must contain complete merged cells",
          )
        }
        let xml = self.fragment_cell(tree, grid, row, column, styles, limit)
        guard xml.length() <= limit - units else {
          @failure.reject(
            "limit-exceeded", "Rich table fragment exceeds source budget",
          )
        }
        units += xml.length()
        output.write_string(xml)
      }
    }
    output.write_string("</od:tr>")
  }
  output.write_string("</od:tbl>")
  output.to_string()
}
