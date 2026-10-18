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
) -> ParagraphRange raise @failure.Failure {
  self.paragraph_range_in(self.document(), tree, selection, structural~)
}

///|
fn Session::paragraph_range_in(
  self : Session,
  document : @xml.Document,
  tree : WordTree,
  selection : Selection,
  structural~ : Bool,
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
  let paragraphs = siblings[siblings.search(first.id).unwrap():siblings
  .search(last.id)
  .unwrap() +
  1].to_owned()
  for id in paragraphs {
    guard tree.nodes[id].uri == word_uri && tree.nodes[id].name == "p" else {
      @failure.reject("protected-content", "Range crosses protected content")
    }
    tree.check_editable_paragraph(id, part=self.main, pictures=true)
    self.check_native_pictures(tree, id)
    if structural {
      tree.check_structure_paragraph(id)
    }
  }
  if !check_layout {
    return { start, end, paragraphs, }
  }
  let flow = self.flow_from(document)
  let all = flow.paragraphs.copy()
  for table in flow.tables {
    for row in table.rows {
      for cell in row {
        all.append(cell)
      }
    }
  }
  let reasons = Map::from_array(all.map(p => (p.id, p.readOnlyReason)))
  for id in paragraphs {
    guard reasons.get(id) == Some("") else {
      @failure.reject("protected-content", "Range crosses protected content")
    }
  }
  { start, end, paragraphs, }
}

///|
/// Reads a supported plain-text range in document order, with LF paragraph separators.
/// Whole-cell ranges use tabs between cells and LF after each selected row.
/// This query preserves selection, revision, history and layout; oversized output fails.
/// Cut preflight rejects pictures until the clipboard can retain their resources.
pub fn Session::selected_text(
  self : Session,
  revision : Int,
  selection : Selection,
  cut~ : Bool = false,
) -> String raise @failure.Failure {
  self.check_revision(revision)
  let tree = WordTree::new(self.document())
  let cells = self.table_format_range(tree, selection)
  let whole_cells = cells is Some(_)
  let range = cells.unwrap_or_else(() => {
    self.paragraph_range(tree, selection, structural=false)
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
      guard !tree.has_picture_range(
        texts.filter(item => item.paragraph == p),
        start,
        end,
      ) else {
        @failure.reject(
          "protected-content", "Cutting pictures requires rich clipboard support",
        )
      }
    }
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
    let text = self
      .editable_texts(paragraph)
      .map(node => inline_text(tree.nodes[node.id]))
      .join("")
    let start = if paragraph == range.start.paragraph {
      range.start.offset
    } else {
      0
    }
    let end = if paragraph == range.end.paragraph {
      range.end.offset
    } else {
      text.length()
    }
    units += end - start + separator.length()
    guard units <= command_limit else {
      @failure.reject("limit-exceeded", "Selection text exceeds UTF-16 budget")
    }
    output.write_string(separator)
    output.write_string(
      text[start:end].to_owned().replace_all(old="\u2028", new="\n"),
    )
  }
  if whole_cells {
    output.write_string("\n")
  }
  output.to_string()
}
