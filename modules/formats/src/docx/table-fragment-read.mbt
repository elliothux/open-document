///|
fn Session::read_table_fragment(
  self : Session,
  xml : String,
  parts : Map[String, @xml.Document],
  edits : Map[String, Array[@xml.Edit]],
  created : Map[String, @xml.Document],
  media : Map[String, Bytes],
  added_media : Map[String, Bytes],
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
  let document = self.import_fragment_numbering(document, parts, edits, created)
  let document = self.import_fragment_links(document, parts, edits, created)
  let document = self.import_fragment_bookmarks(document)
  let (document, pictures) = self.import_fragment_drawings(
    document, parts, edits, created, media, added_media,
  )
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
  check_fragment_content(tree, nodes, pictures, fields=true)
  guard tree.child(table, "tblGrid") is Some(_) else {
    @failure.reject("invalid-table", "Rich table requires a complete grid")
  }
  let view = { ..self, parts, media, }
  let model = view.flow_from(document).tables
    .get(0)
    .unwrap_or_else(() => {
      @failure.reject("invalid-table", "Rich table has no supported grid")
    })
  let grid = view.check_fragment_table(tree, model)
  let changes = []
  for row in model.rows {
    for paragraphs in row {
      for paragraph in paragraphs {
        let stops = tree
          .child(paragraph.id, "pPr")
          .map(p => tree.paragraph_tabs(p, []))
          .unwrap_or([])
        let markup = view.tab_markup(tree, paragraph.id, stops, style=Clear)
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
    read_table_grid(WordTree::new(next), view.flow_from(next).tables[0], 0, 0),
  )
}

///|
fn Session::check_fragment_table(
  self : Session,
  tree : WordTree,
  model : @layout.Table,
) -> TableGrid raise @failure.Failure {
  guard tree.child(model.id, "tblGrid") is Some(_) else {
    @failure.reject("invalid-table", "Rich table requires a complete grid")
  }
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
    tree.check_merge_cell(cell, self.main, pictures=true, fields=true)
  }
  for row in model.rows {
    for paragraphs in row {
      for paragraph in paragraphs {
        guard paragraph.readOnlyReason.is_empty() else {
          @failure.reject("protected-content", paragraph.readOnlyReason)
        }
      }
    }
  }
  grid
}
