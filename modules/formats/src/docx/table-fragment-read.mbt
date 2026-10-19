///|
fn Session::read_table_fragment(
  self : Session,
  xml : String,
  parts : Map[String, @xml.Document],
  edits : Map[String, Array[@xml.Edit]],
  created : Map[String, @xml.Document],
) -> (@xml.Document, TableGrid) raise @failure.Failure {
  let limit = self.opc.budget.entry_bytes.min(history_byte_limit / 2)
  guard !xml.is_empty() && xml.length() <= limit else {
    @failure.reject(
      "limit-exceeded", "Rich table fragment exceeds source budget",
    )
  }
  let source = "<od:document xmlns:od=\"\{word_uri}\"><od:body>" +
    xml +
    "<od:p/></od:body></od:document>"
  let document = @xml.Document::parse(
    @utf8.encode(source),
    "table-fragment",
    self.opc.budget.xml_depth,
    self.opc.budget.entry_bytes,
  )
  let document = self.import_fragment_links(document, parts, edits, created)
  let document = self.import_fragment_bookmarks(document)
  let tree = WordTree::new(document)
  let body = tree.child(0, "body").unwrap()
  guard tree.children[body].length() == 2 &&
    tree.table_children(body, "tbl").length() == 1 else {
    @failure.reject(
      "invalid-operation", "Rich clipboard requires one native table",
    )
  }
  let table = tree.table_children(body, "tbl")[0]
  let nodes = tree.descendants(table)
  let mut units = 0
  for id in nodes {
    let node = tree.nodes[id]
    guard node.uri == word_uri else {
      @failure.reject(
        "protected-content", "Foreign rich table content is unsupported",
      )
    }
    if node.name == "t" {
      guard node.text.length() <= command_limit - units else {
        @failure.reject(
          "limit-exceeded", "Rich table text exceeds UTF-16 budget",
        )
      }
      units += node.text.length()
    } else {
      guard node.text.trim().is_empty() else {
        @failure.reject(
          "protected-content", "Rich table contains misplaced text",
        )
      }
    }
    guard (
        node.name != "br" ||
        node.attribute("type", uri=word_uri).unwrap_or("textWrapping") ==
        "textWrapping"
      ) &&
      !node.attributes.any(a => {
        a.name.has_suffix("Theme") ||
        a.name.has_prefix("theme") ||
        a.name == "cstheme"
      }) else {
      @failure.reject(
        "protected-content", "Rich table contains unresolved style resources or breaks",
      )
    }
    let children = match node.name {
      "tbl" => ["tblPr", "tblGrid", "tr"]
      "tblPr" => ["tblLayout"]
      "tblGrid" => ["gridCol"]
      "tr" => ["tc"]
      "tc" => ["tcPr", "p"]
      "tcPr" =>
        ["tcW", "gridSpan", "vMerge", "tcBorders", "shd", "tcMar", "vAlign"]
      "p" => ["pPr", "r", "hyperlink", "bookmarkStart", "bookmarkEnd"]
      "hyperlink" => ["r", "bookmarkStart", "bookmarkEnd"]
      "r" => ["rPr", "t", "tab", "br", "cr"]
      "pPr" =>
        [
          "rPr", "spacing", "ind", "jc", "pageBreakBefore", "autoSpaceDE", "autoSpaceDN",
          "tabs", "bidi", "numPr", "outlineLvl", "keepLines", "keepNext", "widowControl",
        ]
      "rPr" =>
        [
          "rFonts", "sz", "color", "b", "i", "lang", "bCs", "iCs", "szCs", "u", "strike",
          "highlight", "vertAlign", "cs", "rtl",
        ]
      "tabs" => ["tab"]
      "numPr" => ["numId"]
      "tcBorders" | "tcMar" => ["top", "left", "bottom", "right"]
      _ => []
    }
    guard tree.children[id].all(child => {
        children.contains(tree.nodes[child].name)
      }) &&
      !["pStyle", "rStyle"].contains(node.name) &&
      (node.name != "numId" || node.attribute("val", uri=word_uri) == Some("0")) else {
      @failure.reject(
        "protected-content", "Rich table fragment contains unsupported references or structure",
      )
    }
    if node.name == "hyperlink" {
      tree.check_hyperlink(id)
    }
    if ["tbl", "tblPr", "tblGrid", "tr", "tc", "tcPr", "p", "pPr", "r", "rPr"].contains(
        node.name,
      ) {
      guard node.attributes.is_empty() && node.text.trim().is_empty() else {
        @failure.reject(
          "protected-content", "Rich table identity metadata is unsupported",
        )
      }
    }
  }
  guard tree.child(table, "tblGrid") is Some(_) else {
    @failure.reject("invalid-table", "Rich table requires a complete grid")
  }
  let model = self.flow_from(document).tables
    .get(0)
    .unwrap_or_else(() => {
      @failure.reject("invalid-table", "Rich table has no supported grid")
    })
  guard model.rows.length() > 0 &&
    model.rows.length() <= 1000 &&
    model.widths.length() > 0 &&
    model.widths.length() <= 63 &&
    model.rows.length().to_int64() * model.widths.length().to_int64() <= 4096 else {
    @failure.reject("limit-exceeded", "Rich table dimensions exceed budget")
  }
  let grid = read_table_grid(tree, model, 0, 0)
  for spans in model.columnSpans {
    guard spans.all(span => span > 0) &&
      spans.fold(init=0, (sum, span) => sum + span) == model.widths.length() else {
      @failure.reject(
        "invalid-table", "Rich table rows must cover the complete grid",
      )
    }
  }
  tree.check_table_structure(grid, columns=true)
  for cell in grid.cells.flatten() {
    tree.check_merge_cell(cell, self.main)
  }
  let changes = []
  for row in model.rows {
    for paragraphs in row {
      for paragraph in paragraphs {
        guard paragraph.readOnlyReason.is_empty() else {
          @failure.reject("protected-content", paragraph.readOnlyReason)
        }
        let stops = tree
          .child(paragraph.id, "pPr")
          .map(p => tree.paragraph_tabs(p, []))
          .unwrap_or([])
        let markup = self.tab_markup(tree, paragraph.id, stops, style=Clear)
        let props = formatted_properties(
          tree,
          document,
          paragraph.id,
          "pPr",
          Map([]),
          nested=Map([("tabs", markup)]),
        )
        if properties_change(tree, document, paragraph.id, "pPr", props)
          is Some(change) {
          changes.push(change)
        }
      }
    }
  }
  if changes.is_empty() {
    return (document, grid)
  }
  let (next, _) = document.edit_source(changes)
  (
    next,
    read_table_grid(WordTree::new(next), self.flow_from(next).tables[0], 0, 0),
  )
}
