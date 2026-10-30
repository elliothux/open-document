///|
fn Table::measure_rows(
  self : Table,
  cache : ParagraphCache,
  probe : TextProbe,
  page : PageSetup,
  first_row : Int32,
  last_row : Int32,
  profile : Map[String, String],
  additive : Bool,
  decorations~ : Map[(Int32, Int32), PageFrame] = Map([]),
) -> (Array[Double], Array[(Int32, Int32, Array[(Line, Double, Line)], Double)]) raise @failure.Failure {
  let heights = Array::makei(last_row - first_row + 1, i => {
    self.row_minimum_height(first_row + i)
  })
  let cells : Array[(Int32, Int32, Array[(Line, Double, Line)], Double)] = []
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
      let children = self.nestedTables.filter(child => {
        child.row == row && child.column == column
      })
      let decoration = table_decoration(page.width, page.height)
      for paragraph_index in 0..<=paragraphs.length() {
        for child in children {
          if child.table.beforeParagraph != paragraph_index {
            continue
          }
          y += after + gap
          after = 0
          gap = 0
          terminal_gap = 0
          let width = self.cell_width(row, column) -
            margins.left -
            margins.right
          let (nested_lines, nested_height, nested_decoration) = child.table.measure_nested(
            cache,
            probe,
            { ..page, width, left: 0, right: 0, },
            profile,
            additive,
          )
          guard nested_lines.length() <= 32768 - lines.length() else {
            @failure.reject(
              "limit-exceeded", "Nested table line budget exceeded",
            )
          }
          lines.append(nested_lines.map(item => (item.0, item.1 + y, item.2)))
          decoration.append_decoration(nested_decoration, 0, y)
          y += nested_height
        }
        if paragraph_index == paragraphs.length() {
          break
        }
        let paragraph = paragraphs[paragraph_index]
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
          guard line.y >= 0 else {
            @failure.reject(
              "unsupported-layout", "Page or column breaks inside table rows are unsupported",
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
      if !children.is_empty() {
        decorations[(row, column)] = decoration
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
