///|
fn Table::check_grid(self : Table) -> Unit raise @failure.Failure {
  let count = self.rows.length()
  guard count > 0 &&
    self.headerRows >= 0 &&
    self.headerRows <= count &&
    !self.widths.is_empty() &&
    self.heights.length() == count &&
    self.exactHeights.length() == count &&
    self.fills.length() == count &&
    self.margins.length() == count &&
    self.verticalAligns.length() == count &&
    self.columnSpans.length() == count &&
    self.rowSpans.length() == count else {
    @failure.reject("invalid-table", "Table row metadata differs from grid")
  }
  guard self.borders.horizontal.length() == count + 1 &&
    self.borders.horizontal.all(row => row.length() == self.widths.length()) &&
    self.borders.vertical.length() == count &&
    self.borders.vertical.all(row => row.length() == self.widths.length() + 1) &&
    [..self.borders.horizontal.flatten(), ..self.borders.vertical.flatten()].all(edge => {
        edge.width >= 0 &&
        edge.width <= 12 &&
        edge.width * 8 == (edge.width * 8).round() &&
        edge.color.length() == 6 &&
        edge.color.iter().all(c => c.is_ascii_hexdigit())
      },
    ) else {
    @failure.reject("invalid-table", "Invalid table border grid")
  }
  let active = Array::make(self.widths.length(), -1)
  for r, row in self.rows {
    guard !row.is_empty() &&
      row.length() == self.fills[r].length() &&
      row.length() == self.margins[r].length() &&
      row.length() == self.verticalAligns[r].length() &&
      row.length() == self.columnSpans[r].length() &&
      row.length() == self.rowSpans[r].length() &&
      self.heights[r] >= 0 &&
      !self.heights[r].is_inf() &&
      !self.heights[r].is_nan() else {
      @failure.reject("invalid-table", "Invalid table cell metadata")
    }
    let mut column = 0
    for c, _ in row {
      let margin = self.margins[r][c]
      guard [margin.top, margin.right, margin.bottom, margin.left].all(v => {
        v >= 0 && !v.is_nan() && !v.is_inf()
      }) else {
        @failure.reject("invalid-style", "Invalid table cell margins")
      }
      let span = self.columnSpans[r][c]
      let rows = self.rowSpans[r][c]
      guard ["top", "center", "bottom"].contains(self.verticalAligns[r][c]) &&
        span > 0 &&
        span <= self.widths.length() - column &&
        rows >= 0 &&
        rows <= count - r else {
        @failure.reject("invalid-table", "Invalid merged cell bounds")
      }
      guard r >= self.headerRows || rows <= self.headerRows - r else {
        @failure.reject(
          "invalid-table", "Header boundary crosses a vertical merge",
        )
      }
      for index in column..<(column + span) {
        guard (if rows == 0 { active[index] >= r } else { active[index] < r }) else {
          @failure.reject(
            "invalid-table", "Merged table cells overlap or lack a start",
          )
        }
        if rows > 0 {
          active[index] = r + rows - 1
        }
      }
      column += span
      let insets = self.cell_insets(r, c)
      guard self.autoFit || self.cell_width(r, c) > insets.left + insets.right else {
        @failure.reject("invalid-style", "Cell margins leave no text width")
      }
    }
    guard column == self.widths.length() else {
      @failure.reject("invalid-table", "Table row differs from grid")
    }
  }
}

///|
fn Table::row_group_end(self : Table, first : Int) -> Int {
  let mut last = first
  let mut row = first
  while row <= last {
    for span in self.rowSpans[row] {
      last = last.max(row + span - 1)
    }
    row += 1
  }
  last
}

///|
fn Table::cell_width(self : Table, row : Int, cell : Int) -> Double {
  let column = self.columnSpans[row][:cell]
    .iter()
    .fold(init=0, (sum, span) => sum + span)
  self.widths[column:column + self.columnSpans[row][cell]]
  .iter()
  .fold(init=0.0, (sum, width) => sum + width)
}

///|
fn Table::row_top_margin(self : Table, row : Int) -> Double {
  self.margins[row]
  .iter()
  .fold(init=0.0, (value, margin) => value.max(margin.top))
}

///|
fn Pagination::table_rows(
  self : Pagination,
  cache : ParagraphCache,
  probe : TextProbe,
  table : Table,
  first_row : Int,
  last_row : Int,
  profile : Map[String, String],
  images : Images,
  additive : Bool,
) -> Unit raise @failure.Failure {
  let left = table.left(self.page)
  let first = table.rows[first_row].get(0).bind(cell => cell.get(0))
  if first_row == 0 &&
    first.map(p => p.pageBreakBefore).unwrap_or(false) &&
    (
      self.pages.last().unwrap().lines.any(line => !line.caretOnly) ||
      !self.pages.last().unwrap().borders.is_empty()
    ) {
    self.next_page()
  }
  let heights = Array::makei(last_row - first_row + 1, i => {
    table.row_minimum_height(first_row + i)
  })
  let cells : Array[(Int, Int, Array[(Line, Double)], Double)] = []
  for row in first_row..<=last_row {
    for column, paragraphs in table.rows[row] {
      if table.rowSpans[row][column] == 0 {
        continue
      }
      let lines : Array[(Line, Double)] = []
      let margins = table.cell_insets(row, column)
      let mut y = table.row_top_margin(row) + table.border_width(row)
      let mut after = 0.0
      let mut gap = 0.0
      let mut terminal_gap = 0.0
      for paragraph_index, paragraph in paragraphs {
        paragraph.validate_spacing(self.page.height)
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
            table.cell_width(row, column) - margins.left - margins.right,
          ) {
          let line = measured.spaced(paragraph.line, first)
          guard line.y != -1 else {
            @failure.reject(
              "unsupported-layout", "Page breaks inside table rows are unsupported",
            )
          }
          lines.push((line, y))
          y += line.height
          gap = paragraph.line.gap(measured.textHeight)
          first = false
        }
        after = paragraph.after
        terminal_gap = paragraph.line.terminal_gap(paragraph.nominalSize)
      }
      let height = y + after + terminal_gap + margins.bottom
      if table.rowSpans[row][column] == 1 && !table.exactHeights[row] {
        heights[row - first_row] = heights[row - first_row].max(height)
      }
      cells.push((row, column, lines, height))
    }
  }
  for (row, column, _, height) in cells {
    let span = table.rowSpans[row][column]
    if span > 1 && !table.exactHeights[row + span - 1] {
      let end = row - first_row + span
      let available = heights[row - first_row:end]
        .iter()
        .fold(init=0.0, (sum, value) => sum + value)
      heights[end - 1] += (height - available).max(0)
    }
  }
  let total = heights.iter().fold(init=0.0, (sum, value) => sum + value)
  // shortcut: Vertical-merge groups stay on one page until split-row continuation is implemented.
  let bottom = table.border_width(last_row + 1)
  self.fit(total + bottom)
  if first_row >= table.headerRows &&
    table.headerRows > 0 &&
    self.y == self.page.top &&
    first_row > 0 {
    let header = Pagination::new(self.page)
    let ready = try {
      header.table_rows(
        cache,
        probe,
        table,
        0,
        table.headerRows - 1,
        profile,
        images,
        additive,
      )
      header.y - self.page.top + total + bottom <=
      self.page.height - self.page.top - self.page.bottom
    } catch {
      @failure.Failure(code="layout-overflow", ..) => false
      error => raise error
    }
    if ready {
      let page = header.pages[0]
      guard page.lines.length() <= 32768 - self.count else {
        @failure.reject("limit-exceeded", "Repeated headers exceed line budget")
      }
      self.count += page.lines.length()
      let target = self.pages.last().unwrap()
      target.lines.append(
        page.lines.map(line => { ..line.copy_geometry(), repeated: true, }),
      )
      target.borders.append(page.borders)
      target.fills.append(page.fills)
      target.cellAreas.append(page.cellAreas)
      self.y = header.y
    }
  }
  for (row, column, lines, content_height) in cells {
    let start = row - first_row
    let y = self.y +
      heights[:start].iter().fold(init=0.0, (sum, value) => sum + value)
    let height = heights[start:start + table.rowSpans[row][column]]
      .iter()
      .fold(init=0.0, (sum, value) => sum + value)
    let mut x = left
    for c in 0..<column {
      x += table.cell_width(row, c)
    }
    let width = table.cell_width(row, column)
    self.pages.last().unwrap().cellAreas.push({
      x,
      y,
      width,
      height,
      paragraphs: table.rows[row][column].map(p => p.id),
    })
    let color = table.fills[row][column]
    if !color.is_empty() {
      self.pages.last().unwrap().fills.push({ x, y, width, height, color, })
    }
    let extra = (height - content_height).max(0)
    let shift = match table.verticalAligns[row][column] {
      "center" => extra / 2
      "bottom" => extra
      _ => 0
    }
    for (line, offset) in lines {
      let line = if table.exactHeights[row + table.rowSpans[row][column] - 1] {
        { ..line, cellClip: Some({ x, y, width, height, }), }
      } else {
        line
      }
      self.place(
        line,
        x + table.cell_insets(row, column).left,
        y + offset + shift,
        images,
      )
    }
  }
  table.paint_borders(
    self.pages.last().unwrap(),
    first_row,
    last_row,
    left,
    self.y,
    heights,
  )
  self.y += total
}
