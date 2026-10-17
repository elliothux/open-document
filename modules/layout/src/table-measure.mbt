///|
fn Table::measure_rows(
  self : Table,
  cache : ParagraphCache,
  probe : TextProbe,
  page : PageSetup,
  first_row : Int,
  last_row : Int,
  profile : Map[String, String],
  additive : Bool,
) -> (Array[Double], Array[(Int, Int, Array[(Line, Double, Line)], Double)]) raise @failure.Failure {
  let heights = Array::makei(last_row - first_row + 1, i => {
    self.row_minimum_height(first_row + i)
  })
  let cells : Array[(Int, Int, Array[(Line, Double, Line)], Double)] = []
  for row in first_row..<=last_row {
    for column, paragraphs in self.rows[row] {
      if self.rowSpans[row][column] == 0 {
        continue
      }
      let lines : Array[(Line, Double, Line)] = []
      let margins = self.cell_insets(row, column)
      let mut y = self.row_top_margin(row) + self.border_width(row)
      let mut after = 0.0
      let mut gap = 0.0
      let mut terminal_gap = 0.0
      for paragraph_index, paragraph in paragraphs {
        paragraph.validate_spacing(page.height)
        guard !paragraph.pageBreakBefore ||
          (row == 0 && column == 0 && paragraph_index == 0) else {
          @failure.reject(
            "unsupported-layout", "Page breaks inside table rows are unsupported",
          )
        }
        y += if additive {
          after + paragraph.before
        } else {
          after.max(paragraph.before)
        }
        y += gap
        let mut first = true
        for
          measured in cache.lines(
            probe,
            paragraph,
            profile,
            self.cell_width(row, column) - margins.left - margins.right,
            inTable=true,
          ) {
          let line = measured.spaced(paragraph.line, first)
          guard line.y != -1 else {
            @failure.reject(
              "unsupported-layout", "Page breaks inside table rows are unsupported",
            )
          }
          lines.push((line, y, measured.spaced(paragraph.line, true)))
          y += line.height
          gap = paragraph.line.gap(measured.textHeight)
          first = false
        }
        after = paragraph.after
        terminal_gap = paragraph.line.terminal_gap(paragraph.nominalSize)
      }
      let height = y + after + terminal_gap + margins.bottom
      if self.rowSpans[row][column] == 1 && !self.exactHeights[row] {
        heights[row - first_row] = heights[row - first_row].max(height)
      }
      cells.push((row, column, lines, height))
    }
  }
  for (row, column, _, height) in cells {
    let span = self.rowSpans[row][column]
    if span > 1 && !self.exactHeights[row + span - 1] {
      let end = row - first_row + span
      let available = heights[row - first_row:end]
        .iter()
        .fold(init=0.0, (sum, value) => sum + value)
      heights[end - 1] += (height - available).max(0)
    }
  }
  (heights, cells)
}
