///|
fn fragment_paragraph(
  tree : WordTree,
  paragraph : @layout.Paragraph,
  styles : Styles,
  document : @xml.Document,
  limit : Int,
  links : Map[String, @opc.Relationship],
  bookmarks : Map[String, Bool],
  markers : Map[Int, String],
  numbers : Map[Int, (Int, Int)],
  pictures : Map[Int, String],
  fields~ : Map[Int, String] = Map([]),
  start~ : Int = 0,
  end~ : Int = 2147483647,
) -> String raise @failure.Failure {
  guard paragraph.readOnlyReason.is_empty() &&
    tree.children[paragraph.id].all(id => {
      (tree.nodes[id].uri == math_uri && tree.nodes[id].name == "oMath") ||
      (
        tree.nodes[id].uri == word_uri &&
        (
          ["pPr", "r", "hyperlink", "fldSimple"].contains(tree.nodes[id].name) ||
          tree.is_bookmark(id)
        )
      )
    }) else {
    @failure.reject(
      "protected-content", "Rich cell fragments require supported ordinary paragraphs without review identities",
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
  let number = numbers.get(paragraph.id)
  let mark = styles.character_style(tree, paragraph.id, None, [])
  let mark = if tree.child(paragraph.id, "pPr") is Some(p) {
    let value = styles.run_character_style(tree, p, mark, [])
    { ..value, underline: mark.underline, }
  } else {
    mark
  }
  let mark = paragraph.marker
    .map(marker => mark.font_runs(marker.text, styles.themes)[0].0)
    .unwrap_or(mark)
  let nested = Map([
    (
      "rPr",
      if number is Some(_) {
        formatted_properties(
          tree,
          document,
          paragraph.id,
          "rPr",
          mark.fragment_format().properties(),
        )
      } else {
        ""
      },
    ),
    (
      "numPr",
      number
      .map(reference => list_properties(reference.0, reference.1))
      .unwrap_or(
        "<od:numPr xmlns:od=\"\{word_uri}\"><od:numId od:val=\"0\"/></od:numPr>",
      ),
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
  for id in tree.children[paragraph.id] {
    if tree.nodes[id].name == "hyperlink" {
      tree.check_hyperlink(id)
      guard !tree.children[id].is_empty() &&
        tree.children[id].all(child => {
          (tree.nodes[child].uri == word_uri && tree.nodes[child].name == "r") ||
          tree.is_bookmark(child)
        }) else {
        @failure.reject(
          "protected-content", "Rich hyperlink copies require ordinary runs without identities",
        )
      }
    }
  }
  let runs : Array[Int?] = []
  for id in tree.children[paragraph.id] {
    if tree.nodes[id].name == "hyperlink" {
      runs.append(tree.children[id].map(child => Some(child)))
    } else if tree.nodes[id].name != "pPr" {
      runs.push(Some(id))
    }
  }
  if tree.paragraph_runs(paragraph.id, running=true, math=true).is_empty() {
    runs.push(tree.child(paragraph.id, "pPr"))
  }
  let mut active_link : Int? = None
  let mut cursor = 0
  for run in runs {
    if run is Some(id) && tree.is_bookmark(id) && !markers.contains(id) {
      continue
    }
    let count = run
      .map(id => {
        if tree.nodes[id].name == "r" {
          tree.children[id]
          .filter(child => {
            ["t", "tab", "br", "cr", "drawing"].contains(tree.nodes[child].name)
          })
          .fold(init=0, (sum, child) => {
            sum + inline_text(tree.nodes[child]).length()
          })
        } else if ["fldSimple", "oMath"].contains(tree.nodes[id].name) {
          1
        } else {
          0
        }
      })
      .unwrap_or(0)
    let left = (start - cursor).clamp(min=0, max=count)
    let right = (end - cursor).clamp(min=0, max=count)
    cursor += count
    if count > 0 && left == right {
      continue
    }
    let link = run.bind(run => tree.run_hyperlink(run))
    if link != active_link {
      if active_link is Some(_) {
        output.write_string("</od:hyperlink>")
      }
      if link is Some(id) {
        let opening = fragment_link_opening(tree, id, links, bookmarks)
        guard opening.length() + 15 <= limit - units else {
          @failure.reject(
            "limit-exceeded", "Rich hyperlink exceeds source budget",
          )
        }
        units += opening.length() + 15
        output.write_string(opening)
      }
      active_link = link
    }
    if run is Some(id) && markers.get(id) is Some(markup) {
      guard markup.length() <= limit - units else {
        @failure.reject("limit-exceeded", "Rich bookmark exceeds source budget")
      }
      units += markup.length()
      output.write_string(markup)
      continue
    }
    if run is Some(id) && tree.nodes[id].uri == math_uri {
      guard paragraph.spans.iter().find_first(span => span.node == id)
        is Some({ drawing: Some({ content: Fraction(fraction), .. }), .. }) else {
        @failure.reject(
          "protected-content", "Rich fraction layout is unavailable",
        )
      }
      let xml = math_fraction_markup(
        fraction.numerator,
        fraction.denominator,
        style=Some(fraction.style),
      )
      guard xml.length() <= limit - units else {
        @failure.reject(
          "limit-exceeded", "Rich fraction exceeds clipboard budget",
        )
      }
      units += xml.length()
      output.write_string(xml)
      continue
    }
    if run is Some(id) && tree.nodes[id].name == "fldSimple" {
      guard fields.get(id) is Some(value) else {
        @failure.reject(
          "protected-content", "Rich field copy requires its current layout value",
        )
      }
      let xml = fragment_field_markup(
        tree,
        document,
        paragraph.id,
        id,
        styles,
        value,
        limit - units,
      )
      units += xml.length()
      output.write_string(xml)
      continue
    }
    if run is Some(run) && tree.nodes[run].name == "r" {
      guard tree.children[run].all(id => {
        let node = tree.nodes[id]
        node.uri == word_uri &&
        (
          ["rPr", "t", "tab", "br", "cr"].contains(node.name) ||
          node.name == "drawing"
        ) &&
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
    let xml = fragment_run_markup(
      tree,
      document,
      paragraph.id,
      run,
      style,
      styles.themes,
      pictures,
      limit,
      start=left,
      end=right,
    )
    guard xml.length() <= limit - units else {
      @failure.reject(
        "limit-exceeded", "Rich cell paragraph exceeds source budget",
      )
    }
    units += xml.length()
    output.write_string(xml)
  }
  if active_link is Some(_) {
    output.write_string("</od:hyperlink>")
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
  links : Map[String, @opc.Relationship],
  bookmarks : Map[String, Bool],
  markers : Map[Int, String],
  numbers : Map[Int, (Int, Int)],
  pictures : Map[Int, String],
  fields : Map[Int, String],
) -> String raise @failure.Failure {
  let cell = grid.cells[row][column]
  tree.check_merge_cell(cell, self.main, pictures=true, fields=true, math=true)
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
      links,
      bookmarks,
      markers,
      numbers,
      pictures,
      fields~,
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
  fields : Map[Int, String],
  numbers? : Map[Int, (Int, Int)],
  markers? : Map[Int, String],
  body~ : Bool = false,
) -> String raise @failure.Failure {
  let limit = self.opc.budget.entry_bytes.min(history_byte_limit / 2)
  let output = StringBuilder()
  let properties = if body {
    tree
    .child(grid.table, "tblPr")
    .map(id => {
      check_fragment_content(tree, tree.descendants(id), Map([]))
      let diagnostics : Array[String] = []
      tree.diagnose_properties(id, self.main, diagnostics)
      guard diagnostics.is_empty() else {
        @failure.reject(
          "protected-content", "Table style resources require portable table styles",
        )
      }
      tree.standalone_markup(self.document(), id)
    })
    .unwrap_or("<od:tblPr/>")
  } else {
    "<od:tblPr><od:tblLayout od:type=\"fixed\"/></od:tblPr>"
  }
  output.write_string(
    "<od:tbl xmlns:od=\"\{word_uri}\">\{properties}<od:tblGrid>",
  )
  for width in grid.model.widths[left:right] {
    output.write_string("<od:gridCol od:w=\"\{(width*20).round().to_int()}\"/>")
  }
  output.write_string("</od:tblGrid>")
  let styles = self.styles([])
  let (numbering, numbers) = match numbers {
    Some(numbers) => ("", numbers)
    None =>
      self.fragment_numbering(
        tree, grid, top, bottom, left, right, styles, limit,
      )
  }
  output.write_string(numbering)
  let links = self.hyperlink_relationships()
  let bookmarks = tree.bookmark_targets()
  let markers = markers.unwrap_or_else(() => {
    fragment_bookmark_markers(tree, grid, top, bottom, left, right)
  })
  let pictures : Map[Int, String] = Map([])
  for row in top..<bottom {
    for column, cell in grid.cells[row] {
      let start = grid.starts[row][column]
      if start >= left && start < right {
        for id in tree.descendants(cell) {
          if tree.nodes[id].uri == word_uri && tree.nodes[id].name == "drawing" {
            pictures[id] = self.fragment_drawing(tree, id, limit)
          }
        }
      }
    }
  }
  let mut units = output.to_string().length() + 10
  let mut hyperlink_count = 0
  for row in top..<bottom {
    output.write_string("<od:tr>")
    units += 17
    if body {
      let properties = tree.copy_row_properties(self.document(), grid.rows[row])
      guard properties.length() <= limit - units else {
        @failure.reject(
          "limit-exceeded", "Rich table fragment exceeds source budget",
        )
      }
      units += properties.length()
      output.write_string(properties)
    }
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
        for paragraph in tree.table_children(cell, "p") {
          hyperlink_count += tree.children[paragraph]
            .filter(id => tree.nodes[id].name == "hyperlink")
            .length()
          guard hyperlink_count <= 4096 else {
            @failure.reject(
              "limit-exceeded", "Rich table hyperlinks exceed 4096",
            )
          }
        }
        let xml = self.fragment_cell(
          tree, grid, row, column, styles, limit, links, bookmarks, markers, numbers,
          pictures, fields,
        )
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
