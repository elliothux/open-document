///|
priv struct TablePageSpace {
  initial : Double
  starts : Array[Double]
  tops : Array[Double]
  capacities : Array[Double]
}

///|
fn TablePageSpace::index(
  self : TablePageSpace,
  position : Double,
) -> Int32 raise @failure.Failure {
  guard position >= 0 && position < self.starts.last().unwrap() else {
    @failure.reject("limit-exceeded", "Merged table exceeds page budget")
  }
  for low = 0, high = self.tops.length(); low < high; {
    let middle = (low + high) / 2
    if self.starts[middle + 1] <= position {
      continue middle + 1, high
    } else {
      continue low, middle
    }
  } nobreak {
    low
  }
}

///|
fn TablePageSpace::start(self : TablePageSpace, page : Int32) -> Double {
  self.starts[page]
}

///|
fn TablePageSpace::end(
  self : TablePageSpace,
  position : Double,
) -> Double raise @failure.Failure {
  self.starts[self.index(position) + 1]
}

///|
fn TablePageSpace::y(
  self : TablePageSpace,
  position : Double,
  page : Int32,
) -> Double {
  (if page == 0 { self.initial } else { self.tops[page] }) +
  position -
  self.starts[page]
}

///|
fn Table::continued_cell_lines(
  self : Table,
  space : TablePageSpace,
  row : Int32,
  column : Int32,
  lines : Array[(Line, Double, Line)],
  height : Double,
  start : Double,
) -> (Array[(Line, Double)], Double) raise @failure.Failure {
  let placed : Array[(Line, Double)] = []
  let top = self.row_top_margin(row) + self.border_width(row)
  let margin = self.margins[row][column].bottom
  let clipped = self.exactHeights[row + self.rowSpans[row][column] - 1]
  let mut base = start
  let mut origin = 0.0
  let mut delta = 0.0
  let mut first = 0
  let mut index = 0
  let mut content_end = start
  while index < lines.length() {
    let (normal, offset, initial) = lines[index]
    let line = if index == first && index > 0 { initial } else { normal }
    let position = base +
      offset -
      origin -
      (if index > first { delta } else { 0.0 })
    let boundary = space.end(base)
    let kept = self.kept_paragraph_height(row, column, lines, index)
    let required = if kept is Some(kept) &&
      top + kept + margin <= space.capacities[space.index(base)] {
      kept
    } else {
      line.height
    }
    if position + required + margin > boundary + 0.000001 &&
      !(clipped &&
      top + line.height + margin > space.capacities[space.index(base)]) {
      guard base > space.start(space.index(base)) ||
        index > first ||
        (space.index(base) == 0 && space.initial > space.tops[0]) ||
        space.capacities[space.index(base) + 1:(space.index(base) + 3).min(
          space.capacities.length(),
        )]
        .iter()
        .any(capacity => top + required + margin <= capacity) else {
        @failure.reject(
          "layout-overflow", "A merged cell line and its margins exceed the page content area",
        )
      }
      base = boundary
      if index > 0 {
        origin = offset - top
        delta = normal.height - initial.height
      }
      first = index
      continue
    }
    placed.push((line, position))
    content_end = position + line.height + margin
    index += 1
  }
  let boundary = space.end(base)
  (placed, content_end.max((base + height - origin - delta).min(boundary)))
}

///|
fn Pagination::continue_table_group(
  self : Pagination,
  cache : ParagraphCache,
  probe : TextProbe,
  table : Table,
  first_row : Int32,
  last_row : Int32,
  heights : Array[Double],
  cells : Array[(Int32, Int32, Array[(Line, Double, Line)], Double)],
  profile : Map[String, String],
  images : Images,
  additive : Bool,
) -> Unit raise @failure.Failure {
  let bottom = table.borders.horizontal.fold(init=0.0, (value, edges) => {
    edges.fold(init=value, (value, edge) => value.max(edge.extent()))
  })
  let full = self.page.height - self.page.top - self.page.bottom - bottom
  let mut required = 0.05
  for (row, column, lines, _) in cells {
    let top = table.row_top_margin(row) + table.border_width(row)
    let margin = table.margins[row][column].bottom
    for index, line in lines {
      let kept = table.kept_paragraph_height(row, column, lines, index)
      let height = if kept is Some(height) && top + height + margin <= full {
        height
      } else {
        line.2.height
      }
      required = required.max(top + height + margin)
    }
  }
  let minimum_full = [
    self.page_at(self.pages.length() - 1),
    self.page_at(self.pages.length()),
    self.page_at(self.pages.length() + 1),
  ].fold(init=full, (value, page) => {
    value.min(page.height - page.top - page.bottom - bottom)
  })
  let header = Pagination::new(self.page)
  // shortcut: Reserve header space per merge group; refine per-page reservations for mixed tall-line headers.
  let repeat = if first_row >= table.headerRows && table.headerRows > 0 {
    try {
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
      header.pages.length() == 1 &&
      header.y - self.page.top + required <= minimum_full
    } catch {
      @failure.Failure(code="layout-overflow", ..) => false
      error => raise error
    }
  } else {
    false
  }
  let header_height = if repeat { header.y - self.page.top } else { 0 }
  if repeat && self.y == self.page.top {
    self.append_table_header(header.pages[0])
    self.y = header.y
  }
  let tops : Array[Double] = []
  let capacities : Array[Double] = []
  let page_starts : Array[Double] = [0]
  let base_page = self.pages.length() - 1
  for index in base_page..<(1024 * self.columns.count) {
    let page = self.page_at(index)
    let raw_capacity = page.height -
      page.top -
      page.bottom -
      bottom -
      header_height
    guard raw_capacity > 0 else {
      @failure.reject(
        "layout-overflow", "Table borders leave no page content area",
      )
    }
    let top = self.wrapping_floor(index, page.top, page.height) + header_height
    let capacity = (page.height - page.bottom - bottom - top).max(0)
    tops.push(top)
    capacities.push(capacity)
    let available = if index == base_page {
      (page.height - page.bottom - bottom - self.y.max(top)).max(0)
    } else {
      capacity
    }
    page_starts.push(page_starts.last().unwrap() + available)
  }
  let space = {
    initial: self.y.max(tops[0]),
    starts: page_starts,
    tops,
    capacities,
  }
  let count = last_row - first_row + 1
  let starts = Array::make(count, 0.0)
  let ends = Array::make(count, 0.0)
  let needed = Array::make(count, 0.0)
  let positioned : Array[Array[(Line, Double)]] = []
  let owners : Array[Array[Int32]] = Array::makei(count, _ => [])
  for index, (row, _, _, _) in cells {
    owners[row - first_row].push(index)
    positioned.push([])
  }
  let mut cursor = 0.0
  for row in first_row..<=last_row {
    let index = row - first_row
    let boundary = space.end(cursor)
    if !table.splitRows[row] &&
      cursor > space.start(space.index(cursor)) &&
      heights[index] > boundary - cursor {
      cursor = boundary
      if index > 0 {
        ends[index - 1] = cursor
      }
    }
    starts[index] = cursor
    for cell in owners[index] {
      let (_, column, lines, height) = cells[cell]
      let (placed, end) = table.continued_cell_lines(
        space, row, column, lines, height, cursor,
      )
      positioned[cell] = placed
      let last = index + table.rowSpans[row][column] - 1
      if !table.exactHeights[first_row + last] {
        needed[last] = needed[last].max(end)
      }
    }
    cursor = (cursor + table.row_minimum_height(row)).max(needed[index])
    ignore(space.index((cursor - 0.000001).max(0)))
    ends[index] = cursor
  }
  let final_page = space.index((cursor - 0.000001).max(0))
  for _ in 0..<final_page {
    self.next_page()
    if repeat && capacities[self.pages.length() - base_page - 1] > 0 {
      let repeated = Pagination::new({
        ..self.page,
        top: tops[self.pages.length() - base_page - 1] - header_height,
      })
      repeated.table_rows(
        cache,
        probe,
        table,
        0,
        table.headerRows - 1,
        profile,
        images,
        additive,
      )
      self.append_table_header(repeated.pages[0])
      self.y = repeated.y
    }
  }
  // Row boundaries are settled before painting merged cells or their content.
  for row in first_row..<=last_row {
    let start = starts[row - first_row]
    let end = ends[row - first_row]
    let first_page = space.index(start)
    let last_page = space.index((end - 0.000001).max(start))
    for page in first_page..<=last_page {
      let a = start.max(space.start(page))
      let b = end.min(space.start(page + 1))
      if b <= a && capacities[page] == 0 {
        continue
      }
      table.paint_borders(
        self.pages[base_page + page],
        row,
        row,
        table.left(self.page_at(base_page + page)),
        space.y(a, page),
        [b - a],
      )
    }
  }
  for index, (row, column, _, _) in cells {
    let start = starts[row - first_row]
    let end = ends[row - first_row + table.rowSpans[row][column] - 1]
    let first_page = space.index(start)
    let last_page = space.index((end - 0.000001).max(start))
    let width = table.cell_width(row, column)
    let mut offset = 0.0
    for previous in 0..<column {
      offset += table.cell_width(row, previous)
    }
    let text_page = positioned[index]
      .get(0)
      .map(item => space.index(item.1.min((end - 0.000001).max(start))))
      .unwrap_or(first_page)
    let first_content_end = positioned[index]
      .filter(item => {
        item.1 >= space.start(text_page) && item.1 < space.start(text_page + 1)
      })
      .fold(init=start.max(space.start(text_page)), (value, item) => {
        value.max(item.1 + item.0.height + table.margins[row][column].bottom)
      })
    let extra = (end.min(space.start(text_page + 1)) - first_content_end).max(0)
    let shift = match table.verticalAligns[row][column] {
      "center" => extra / 2
      "bottom" => extra
      _ => 0
    }
    for page in first_page..<=last_page {
      let x = table.left(self.page_at(base_page + page)) + offset
      let a = start.max(space.start(page))
      let b = end.min(space.start(page + 1))
      if b <= a && capacities[page] == 0 {
        continue
      }
      let frame = self.pages[base_page + page]
      let area = {
        x,
        y: space.y(a, page),
        width,
        height: b - a,
        paragraphs: table.rows[row][column].map(p => p.id),
      }
      frame.cellAreas.push(area)
      let color = table.fills[row][column]
      if !color.is_empty() {
        frame.fills.push({ x, y: area.y, width, height: area.height, color, })
      }
      if page > first_page && a >= ends[row - first_row] {
        table.merged_page_edge(frame, row, column, x, area.y, false)
      }
      if page < last_page &&
        b <= starts[row - first_row + table.rowSpans[row][column] - 1] {
        table.merged_page_edge(
          frame,
          row,
          column,
          x,
          area.y + area.height,
          true,
        )
      }
    }
    for (line, position) in positioned[index] {
      let page = if position >= end { last_page } else { space.index(position) }
      let x = table.left(self.page_at(base_page + page)) + offset
      let a = start.max(space.start(page))
      let b = end.min(space.start(page + 1))
      let line = if table.exactHeights[row + table.rowSpans[row][column] - 1] {
        {
          ..line,
          cellClip: Some({ x, y: space.y(a, page), width, height: b - a, }),
        }
      } else {
        line
      }
      self.place(
        line,
        x + table.cell_insets(row, column).left,
        space.y(position, page) + (if page == text_page { shift } else { 0 }),
        images,
        page=base_page + page,
      )
    }
  }
  self.y = space.y(cursor, final_page)
}

///|
fn Table::merged_page_edge(
  self : Table,
  page : PageFrame,
  row : Int32,
  cell : Int32,
  x : Double,
  y : Double,
  bottom : Bool,
) -> Unit raise @failure.Failure {
  let start = self.columnSpans[row][:cell].fold(init=0, (value, span) => {
    value + span
  })
  let boundary = if bottom { row + self.rowSpans[row][cell] } else { row }
  let mut left = x
  for column in start..<(start + self.columnSpans[row][cell]) {
    let edge = self.borders.horizontal[boundary][column]
    if edge.width > 0 {
      page.paint_table_border(
        { x: left, y, width: self.widths[column], height: 0, },
        edge,
      )
    }
    left += self.widths[column]
  }
}
