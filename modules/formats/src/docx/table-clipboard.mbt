///|
/// Reads selected owners as quoted TSV and a portable fragment; cut checks picture retention and removal.
/// Supply the current layout when selected cells contain page fields.
pub fn Session::table_clipboard(
  self : Session,
  revision : Int,
  selection : Selection,
  cut~ : Bool = false,
  layout? : @layout.Layout,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let tree = WordTree::new(self.document())
  let selected = self.table_cell_range(
    tree,
    selection,
    pictures=true,
    fields=true,
  )
  let grid = selected
    .map(range => range.grid)
    .unwrap_or_else(() => self.table_grid(tree, selection, fields=true))
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
    tree.check_merge_cell(cell, self.main, pictures=true, fields=true)
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
  let values = self.field_values(
    tree,
    owners
    .map(cell => tree.descendants(cell))
    .flatten()
    .filter(id => {
      tree.nodes[id].uri == word_uri && tree.nodes[id].name == "fldSimple"
    }),
    layout,
  )
  fn displayed(span : @layout.Span) -> String {
    if span.field.is_empty() {
      span.text
    } else {
      values[tree.nodes[tree.nodes[span.node].parent].parent]
    }
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
        sum + displayed(span).length().to_int64()
      })
    })
    guard size <= (command_limit - units).to_int64() else {
      @failure.reject(
        "limit-exceeded", "Copied table text exceeds UTF-16 budget",
      )
    }
    let text = paragraphs
      .map(p => p.spans.map(displayed).join(""))
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
    self.capture_table_fragment(
      tree, grid, top, bottom, left, right, owners, values,
    ),
  ) catch {
    @failure.Failure(code="protected-content", message~, ..) => {
      reason = message
      Json::null()
    }
    error => raise error
  }
  if cut {
    for cell in owners {
      for id in tree.descendants(cell) {
        if tree.nodes[id].uri == word_uri &&
          ["drawing", "fldSimple"].contains(tree.nodes[id].name) {
          guard fragment != Json::null() else {
            @failure.reject(
              "protected-content", "Inline object cut requires a complete rich fragment",
            )
          }
          if tree.nodes[id].name == "drawing" {
            ignore(self.editable_picture(tree, id, remove=true))
          }
        }
      }
    }
  }
  {
    "kind": "cells",
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
