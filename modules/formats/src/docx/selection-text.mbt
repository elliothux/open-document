///|
priv struct ParagraphRange {
  start : Position
  end : Position
  paragraphs : Array[Int]
}

///|
fn Session::paragraph_range(
  self : Session,
  tree : WordTree,
  selection : Selection,
  structural~ : Bool,
  fields~ : Bool = false,
  tables~ : Bool = false,
) -> ParagraphRange raise @failure.Failure {
  self.paragraph_range_in(
    self.document(),
    tree,
    selection,
    structural~,
    fields~,
    tables~,
  )
}

///|
fn Session::paragraph_range_in(
  self : Session,
  document : @xml.Document,
  tree : WordTree,
  selection : Selection,
  structural~ : Bool,
  fields~ : Bool = false,
  tables~ : Bool = false,
  check_layout~ : Bool = true,
  check_graphemes~ : Bool = true,
) -> ParagraphRange raise @failure.Failure {
  self.check_position_in(document, selection.anchor, check_graphemes~)
  self.check_position_in(document, selection.focus, check_graphemes~)
  let (start, end) = if tree.nodes[selection.anchor.paragraph].start <
    tree.nodes[selection.focus.paragraph].start ||
    (
      selection.anchor.paragraph == selection.focus.paragraph &&
      selection.anchor.offset <= selection.focus.offset
    ) {
    (selection.anchor, selection.focus)
  } else {
    (selection.focus, selection.anchor)
  }
  let first = tree.nodes[start.paragraph]
  let last = tree.nodes[end.paragraph]
  guard first.parent == last.parent else {
    @failure.reject("protected-content", "Range crosses paragraph containers")
  }
  let siblings = tree.children[first.parent]
  let blocks = siblings[siblings.search(first.id).unwrap():siblings
  .search(last.id)
  .unwrap() +
  1].to_owned()
  let paragraphs : Array[Int] = []
  let continuations : Map[Int, Unit] = Map([])
  let mut cells = 0L
  let mut table_count = 0
  let table_flow = if tables &&
    blocks.any(id => {
      tree.nodes[id].uri == word_uri && tree.nodes[id].name == "tbl"
    }) {
    Some(self.flow_from(document))
  } else {
    None
  }
  for id in blocks {
    if tables &&
      tree.nodes[id].uri == word_uri &&
      tree.nodes[id].name == "tbl" &&
      tree.nodes[first.parent].name == "body" {
      let model = table_flow.unwrap().tables
        .iter()
        .find_first(table => table.id == id)
        .unwrap()
      let grid = self.check_fragment_table(tree, model)
      for r, row in grid.cells {
        for c, cell in row {
          if model.rowSpans[r][c] == 0 {
            for paragraph in tree.table_children(cell, "p") {
              continuations[paragraph] = ()
            }
          }
        }
      }
      table_count += 1
      cells += model.rows.length().to_int64() * model.widths.length().to_int64()
      guard table_count <= 32 && cells <= 4096L else {
        @failure.reject(
          "limit-exceeded", "Selected body tables exceed grid budget",
        )
      }
      paragraphs.append(
        tree
        .descendants(id)
        .filter(child => {
          tree.nodes[child].uri == word_uri && tree.nodes[child].name == "p"
        }),
      )
      continue
    }
    guard tree.nodes[id].uri == word_uri && tree.nodes[id].name == "p" else {
      @failure.reject(
        "protected-content",
        "Range crosses unsupported block: " + tree.nodes[id].name,
      )
    }
    tree.check_editable_paragraph(id, part=self.main, pictures=true, fields~)
    self.check_native_drawings(tree, id)
    if structural {
      tree.check_structure_paragraph(id, running=fields)
    }
    paragraphs.push(id)
  }
  if !check_layout {
    return { start, end, paragraphs, }
  }
  let flow = table_flow.unwrap_or_else(() => self.flow_from(document))
  let all = flow.paragraphs.copy()
  for table in flow.tables {
    for row in table.rows {
      for cell in row {
        all.append(cell)
      }
    }
  }
  let nested = all
    .iter()
    .flat_map(p => p.spans.iter())
    .flat_map(span => {
      match span.drawing {
        Some({ content: @layout.TextBox(_, text), .. }) =>
          text.paragraphs().iter()
        _ => [].iter()
      }
    })
    .collect()
  all.append(nested)
  let reasons = Map::from_array(all.map(p => (p.id, p.readOnlyReason)))
  for id in paragraphs {
    // Validated empty vertical continuations have no visible flow paragraphs.
    guard reasons.get(id) == Some("") || continuations.contains(id) else {
      @failure.reject(
        "protected-content",
        reasons.get(id).unwrap_or("Range paragraph is unavailable"),
      )
    }
  }
  { start, end, paragraphs, }
}

///|
/// Reads a supported plain-text range in document order, with LF paragraph separators.
/// Whole-cell ranges use tabs between cells and LF after each selected row.
/// This query preserves selection, revision, history and layout; oversized output fails.
/// Supply the current layout when the selected range contains page fields.
/// Plain-text cut rejects inline objects; rich clipboard validates their portable source.
pub fn Session::selected_text(
  self : Session,
  revision : Int,
  selection : Selection,
  cut~ : Bool = false,
  layout? : @layout.Layout,
) -> String raise @failure.Failure {
  self.check_revision(revision)
  let tree = WordTree::new(self.document())
  let cells = self.table_format_range(tree, selection, fields=true)
  let whole_cells = cells is Some(_)
  let range = cells.unwrap_or_else(() => {
    self.paragraph_range(
      tree,
      selection,
      structural=false,
      fields=true,
      tables=true,
    )
  })
  if cut {
    let texts = docx_texts(tree)
    for p in range.paragraphs {
      let start = if p == range.start.paragraph {
        range.start.offset
      } else {
        0
      }
      let end = if p == range.end.paragraph {
        range.end.offset
      } else {
        0x7fffffff
      }
      guard !tree.has_drawing_range(
        texts.filter(item => item.paragraph == p),
        start,
        end,
        fields=true,
      ) else {
        @failure.reject(
          "protected-content", "Cutting inline objects requires rich clipboard support",
        )
      }
    }
  }
  let fields = self.selection_field_values(tree, range, layout)
  if range.paragraphs.any(id => {
      tree.nodes[id].parent != tree.nodes[range.start.paragraph].parent
    }) &&
    !whole_cells {
    return self.mixed_range_text(tree, range, fields)
  }
  let output = StringBuilder()
  let mut units = if whole_cells { 1 } else { 0 }
  for index, paragraph in range.paragraphs {
    let separator = if index == 0 {
      ""
    } else {
      let cell = tree.nodes[paragraph].parent
      let previous = tree.nodes[range.paragraphs[index - 1]].parent
      if whole_cells &&
        cell != previous &&
        tree.nodes[cell].parent == tree.nodes[previous].parent {
        "\t"
      } else {
        "\n"
      }
    }
    let text = self.range_paragraph_text(tree, range, paragraph, fields)
    units += separator.length() + text.length()
    guard units <= command_limit else {
      @failure.reject("limit-exceeded", "Selection text exceeds UTF-16 budget")
    }
    output.write_string(separator)
    output.write_string(text)
  }
  if whole_cells {
    output.write_string("\n")
  }
  output.to_string()
}
