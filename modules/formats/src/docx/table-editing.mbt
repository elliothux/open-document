///|
fn Session::table_cell_markup(
  self : Session,
  tree : WordTree,
  range : ParagraphRange,
) -> (String, String) raise @failure.Failure {
  let position = range.start
  let character = self.formatting_styles(tree, {
      start: position,
      end: position,
      paragraphs: [position.paragraph],
    }).0[0]
  let patch = CharacterFormat::new(
    family=Set(character.family),
    size=Set(character.size),
    color=Set(character.color),
    bold=Set(character.bold),
    italic=Set(character.italic),
    underline=Set(character.underline),
    strike=Set(character.strike),
    highlight=Set(character.highlight),
    vertAlign=Set(character.vertAlign),
  )
  patch.validate()
  let paragraph = formatted_properties(
    tree,
    self.document(),
    position.paragraph,
    "pPr",
    ParagraphFormat::new(
      left=Set(0),
      right=Set(0),
      first=Set(0),
      pageBreakBefore=Set(false),
    ).properties(),
  )
  let run = formatted_properties(
    tree,
    self.document(),
    position.paragraph,
    "rPr",
    patch.properties(),
  )
  (paragraph, run)
}

///|
/// Inserts a fixed grid at a supported body range; source deletion and splitting share one history.
pub fn Session::insert_table(
  self : Session,
  revision : Int,
  selection : Selection,
  rows : Int,
  columns : Int,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  guard rows >= 1 &&
    rows <= 1000 &&
    columns >= 1 &&
    columns <= 63 &&
    rows.to_int64() * columns.to_int64() <= 4096L else {
    @failure.reject(
      "invalid-operation", "Table dimensions require 1-1000 rows, 1-63 columns and at most 4096 cells",
    )
  }
  let original = self.document()
  let tree = WordTree::new(original)
  let range = self.paragraph_range(tree, selection, structural=true)
  let body = tree.child(0, "body").unwrap()
  guard tree.nodes[range.start.paragraph].parent == body else {
    @failure.reject(
      "protected-content", "Table insertion requires a body paragraph",
    )
  }
  ignore(self.editable_page_section(tree))
  let flow = self.flow_from(original)
  let width = ((flow.page.width - flow.page.left - flow.page.right) * 20)
    .floor()
    .to_int()
  guard width / columns >= 240 else {
    @failure.reject(
      "invalid-operation", "Page content is too narrow for the requested columns",
    )
  }
  let source_paragraph = flow.paragraphs
    .iter()
    .find_first(p => p.id == range.start.paragraph)
    .unwrap()
  let carry_break = range.start.offset == 0 && source_paragraph.pageBreakBefore
  let (paragraph, run) = self.table_cell_markup(tree, range)
  let bindings = tree.namespace_bindings(range.start.paragraph)
  bindings["od"] = word_uri
  let markup = StringBuilder()
  markup.write_string("<od:tbl")
  for prefix, uri in bindings {
    markup.write_string(
      " \{if prefix.is_empty() { "xmlns" } else { "xmlns:" + prefix }}=\"\{property_attribute(uri)}\"",
    )
  }
  markup.write_string(
    "><od:tblPr><od:tblW od:type=\"dxa\" od:w=\"\{width}\"/><od:tblBorders>",
  )
  for edge in ["top", "left", "bottom", "right", "insideH", "insideV"] {
    markup.write_string(
      "<od:\{edge} od:val=\"single\" od:sz=\"4\" od:color=\"000000\"/>",
    )
  }
  markup.write_string(
    "</od:tblBorders><od:tblLayout od:type=\"fixed\"/><od:tblCellMar><od:top od:w=\"0\" od:type=\"dxa\"/><od:left od:w=\"108\" od:type=\"dxa\"/><od:bottom od:w=\"0\" od:type=\"dxa\"/><od:right od:w=\"108\" od:type=\"dxa\"/></od:tblCellMar></od:tblPr><od:tblGrid>",
  )
  let widths = Array::makei(columns, i => {
    width / columns + (if i < width % columns { 1 } else { 0 })
  })
  for width in widths {
    markup.write_string("<od:gridCol od:w=\"\{width}\"/>")
  }
  markup.write_string("</od:tblGrid>")
  let limit = self.opc.budget.entry_bytes.min(history_byte_limit / 2)
  let cell = "<od:p>\{paragraph}<od:r>\{run}<od:t/></od:r></od:p>"
  guard cell.length().to_int64() * rows.to_int64() * columns.to_int64() <=
    limit.to_int64() else {
    @failure.reject("limit-exceeded", "Table source exceeds history budget")
  }
  for _ in 0..<rows {
    markup.write_string("<od:tr>")
    for width in widths {
      markup.write_string(
        "<od:tc><od:tcPr><od:tcW od:type=\"dxa\" od:w=\"\{width}\"/></od:tcPr>\{cell}</od:tc>",
      )
    }
    markup.write_string("</od:tr>")
  }
  markup.write_string("</od:tbl>")
  guard markup.to_string().length() <= limit else {
    @failure.reject("limit-exceeded", "Table source exceeds history budget")
  }
  let prepared = if range.start.offset == 0 {
    self.prepare_plain_range(selection, "")
  } else {
    Some(self.prepare_structural_range(selection, "\n"))
  }
  let mut candidate = prepared.map(p => p.document).unwrap_or(original)
  let edits = prepared.map(p => p.edit.xml.copy()).unwrap_or([])
  let right = prepared
    .bind(p => p.edit.after)
    .map(s => s.focus.paragraph)
    .unwrap_or(range.start.paragraph)
  let right_node = candidate.node(right)
  let (updated, edit) = candidate.edit_source([
    {
      node: body,
      offset: right_node.start - candidate.node(body).start,
      length: 0,
      xml: markup.to_string(),
    },
  ])
  candidate = updated
  edits.push(edit)
  let inserted = WordTree::new(candidate)
  let siblings = inserted.children[body]
  let table = siblings[siblings.search(right).unwrap() - 1]
  let cell_paragraphs = inserted
    .descendants(table)
    .filter(id => {
      inserted.nodes[id].uri == word_uri && inserted.nodes[id].name == "p"
    })
  let first = cell_paragraphs[0]
  if carry_break {
    for (paragraph, value) in [(first, true), (right, false)] {
      if self.format_paragraph_document(
          candidate,
          {
            anchor: {
              paragraph,
              offset: 0,
              affinity: "after",
              bidiLevel: None,
              frameStart: None,
            },
            focus: {
              paragraph,
              offset: 0,
              affinity: "after",
              bidiLevel: None,
              frameStart: None,
            },
          },
          ParagraphFormat::new(pageBreakBefore=Set(value)),
        )
        is Some((updated, edit)) {
        candidate = updated
        edits.push(edit)
      }
    }
  }
  let candidate_flow = self.flow_from(candidate)
  let new_table = candidate_flow.tables
    .iter()
    .find_first(t => t.id == table)
    .unwrap()
  guard new_table.rows
    .iter()
    .all(row => {
      row.iter().all(cell => cell.iter().all(p => p.readOnlyReason.is_empty()))
    }) else {
    @failure.reject(
      "protected-content", "Inherited table formatting requires unsupported layout",
    )
  }
  let mut bytes = 0
  for edit in edits {
    let count = edit_bytes(edit)
    guard count <= history_byte_limit - bytes else {
      @failure.reject("limit-exceeded", "Table history exceeds budget")
    }
    bytes += count
  }
  let position : Position = {
    paragraph: first,
    offset: 0,
    affinity: "after",
    bidiLevel: None,
    frameStart: None,
  }
  let paragraphs = [..range.paragraphs, ..cell_paragraphs, right]
  self.commit_edit(
    {
      xml: edits,
      parts: Map([]),
      created: Map([]),
      before: self.selection,
      after: Some({ anchor: position, focus: position, }),
      paragraphs,
      bytes,
    },
    candidate,
  )
  self.edit_result(paragraphs)
}
