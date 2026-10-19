///|
/// Reads selected owners as quoted TSV and returns the complete content range for cutting.
pub fn Session::table_clipboard(
  self : Session,
  revision : Int,
  selection : Selection,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let tree = WordTree::new(self.document())
  let selected = self.table_cell_range(tree, selection)
  let grid = selected
    .map(range => range.grid)
    .unwrap_or_else(() => self.table_grid(tree, selection))
  let owners = selected
    .map(range => range.owners)
    .unwrap_or_else(() => {
      let (row, column) = grid.owners[grid.cells[grid.row][grid.column]]
      [grid.cells[row][column]]
    })
  let mut top = grid.rows.length()
  let mut bottom = 0
  let mut left = grid.model.widths.length()
  let mut right = 0
  for cell in owners {
    tree.check_merge_cell(cell, self.main)
    let (row, column) = grid.owners[cell]
    top = top.min(row)
    bottom = bottom.max(row + grid.model.rowSpans[row][column])
    left = left.min(grid.starts[row][column])
    right = right.max(
      grid.starts[row][column] + grid.model.columnSpans[row][column],
    )
  }
  let positions = (bottom - top).to_int64() * (right - left).to_int64()
  guard positions > 0 && positions <= 4096 else {
    @failure.reject("limit-exceeded", "Copied table matrix exceeds cell budget")
  }
  // Each row has one separator per column, including its final LF.
  let mut units = positions.to_int()
  let fields : Map[(Int, Int), String] = Map([])
  for cell in owners {
    let (row, column) = grid.owners[cell]
    let paragraphs = grid.model.rows[row][column]
    let size = paragraphs.fold(init=(paragraphs.length() - 1).to_int64(), (
      sum,
      paragraph,
    ) => {
      paragraph.spans.fold(init=sum, (sum, span) => {
        sum + span.text.length().to_int64()
      })
    })
    guard size <= (command_limit - units).to_int64() else {
      @failure.reject(
        "limit-exceeded", "Copied table text exceeds UTF-16 budget",
      )
    }
    let text = paragraphs
      .map(p => p.spans.map(span => span.text).join(""))
      .join("\n")
      .replace_all(old="\u2028", new="\n")
    let field = @delimited.quote_field(text)
    guard field.length() <= command_limit - units else {
      @failure.reject(
        "limit-exceeded", "Quoted table text exceeds UTF-16 budget",
      )
    }
    units += field.length()
    fields[(row, grid.starts[row][column])] = field
  }
  let output = StringBuilder()
  for row in top..<bottom {
    for column in left..<right {
      if column > left {
        output.write_string("\t")
      }
      output.write_string(fields.get((row, column)).unwrap_or(""))
    }
    output.write_string("\n")
  }
  let mut reason = ""
  let fragment = Json(
    self.capture_table_fragment(tree, grid, top, bottom, left, right, owners),
  ) catch {
    @failure.Failure(code="protected-content", message~, ..) => {
      reason = message
      Json::null()
    }
    error => raise error
  }
  {
    "text": output.to_string(),
    "fragment": fragment,
    "reason": reason,
    "selection": Json(
      if selected is Some(_) {
        selection
      } else {
        tree.cell_contents_selection(owners[0], docx_texts(tree))
      },
    ),
  }
}
