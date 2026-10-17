///|
fn Pagination::split_table_row(
  self : Pagination,
  cache : ParagraphCache,
  probe : TextProbe,
  table : Table,
  row : Int,
  cells : Array[(Int, Int, Array[(Line, Double, Line)], Double)],
  profile : Map[String, String],
  images : Images,
  additive : Bool,
) -> Unit raise @failure.Failure {
  let left = table.left(self.page)
  let bottom = table.border_width(row + 1)
  let limit = self.page.height - self.page.bottom
  let full = limit - self.page.top
  let top = table.row_top_margin(row) + table.border_width(row)
  let mut minimum = table.row_minimum_height(row)
  let whole = cells.fold(init=minimum, (height, cell) => height.max(cell.3)) +
    bottom
  let indices = Array::make(cells.length(), 0)
  let origins = Array::make(cells.length(), 0.0)
  // cantSplit moves the row first, but oversized rows must still make progress.
  if self.y > self.page.top &&
    (!table.splitRows[row] || minimum + bottom > limit - self.y) {
    self.next_page()
  }
  while minimum > 0 || table_row_pending(cells, indices) {
    let required = table.fragment_required(
      row, cells, indices, origins, minimum, full, whole,
    )
    self.repeat_table_header(
      cache, probe, table, row, required, profile, images, additive,
    )
    let available = limit - self.y - bottom
    let ends = indices.copy()
    let deltas = Array::make(cells.length(), 0.0)
    let content = Array::make(cells.length(), 0.0)
    let mut progressed = false
    for index, (_, column, lines, height) in cells {
      let margin = table.margins[row][column].bottom
      if indices[index] > 0 && indices[index] < lines.length() {
        let (normal, _, first) = lines[indices[index]]
        deltas[index] = normal.height - first.height
      }
      while ends[index] < lines.length() {
        let (normal, offset, first) = lines[ends[index]]
        if table.kept_paragraph_height(row, column, lines, ends[index])
          is Some(height) &&
          top + height + margin + bottom <= full &&
          offset - origins[index] - deltas[index] + height + margin > available {
          break
        }
        let initial = ends[index] == indices[index] && indices[index] > 0
        let line = if initial { first } else { normal }
        let offset = offset -
          (if ends[index] > indices[index] { deltas[index] } else { 0.0 })
        let end = offset - origins[index] + line.height
        if end + margin > available {
          break
        }
        ends[index] += 1
        progressed = true
        content[index] = end + margin
      }
      if ends[index] == lines.length() && ends[index] > indices[index] {
        // Trailing paragraph spacing ends at the page boundary without a blank continuation.
        content[index] = content[index].max(
          (height - origins[index] - deltas[index]).min(available),
        )
      }
    }
    let pending = table_row_pending(cells, ends)
    if !progressed && pending {
      guard self.y > self.page.top else {
        @failure.reject(
          "layout-overflow", "A table line and its margins exceed the page content area",
        )
      }
      self.next_page()
      continue
    }
    guard available > 0 else {
      @failure.reject(
        "layout-overflow", "Table borders leave no page content area",
      )
    }
    let height = if pending || minimum > available {
      available
    } else {
      content.fold(init=minimum, (height, value) => height.max(value))
    }
    let mut x = left
    for index, (_, column, lines, _) in cells {
      let width = table.cell_width(row, column)
      let frame = self.pages.last().unwrap()
      frame.cellAreas.push({
        x,
        y: self.y,
        width,
        height,
        paragraphs: table.rows[row][column].map(p => p.id),
      })
      let color = table.fills[row][column]
      if !color.is_empty() {
        frame.fills.push({ x, y: self.y, width, height, color, })
      }
      // ONLYOFFICE aligns only the first fragment containing this cell's text.
      let extra = (height - content[index]).max(0)
      let shift = if indices[index] > 0 {
        0.0
      } else {
        match table.verticalAligns[row][column] {
          "center" => extra / 2
          "bottom" => extra
          _ => 0
        }
      }
      for position in indices[index]..<ends[index] {
        let (normal, offset, first) = lines[position]
        let line = if position == indices[index] && indices[index] > 0 {
          first
        } else {
          normal
        }
        let offset = offset -
          (if position > indices[index] { deltas[index] } else { 0.0 })
        self.place(
          line,
          x + table.cell_insets(row, column).left,
          self.y + offset - origins[index] + shift,
          images,
        )
      }
      indices[index] = ends[index]
      if indices[index] < lines.length() {
        origins[index] = lines[indices[index]].1 - top
      }
      x += width
    }
    table.paint_borders(self.pages.last().unwrap(), row, row, left, self.y, [
      height,
    ])
    minimum = (minimum - height).max(0)
    self.y += height
    if pending || minimum > 0 {
      self.next_page()
    }
  }
}

///|
fn Table::kept_paragraph_height(
  self : Table,
  row : Int,
  column : Int,
  lines : Array[(Line, Double, Line)],
  start : Int,
) -> Double? {
  let paragraph = lines[start].0.paragraph
  if start > 0 && lines[start - 1].0.paragraph == paragraph {
    return None
  }
  let paragraphs = self.rows[row][column]
  let mut index = 0
  while index < paragraphs.length() && paragraphs[index].id != paragraph {
    index += 1
  }
  guard index < paragraphs.length() &&
    (
      paragraphs[index].keepLines ||
      (paragraphs[index].keepNext && index + 1 < paragraphs.length())
    ) else {
    return None
  }
  let mut end = start
  while end + 1 < lines.length() {
    if lines[end + 1].0.paragraph == paragraphs[index].id {
      end += 1
    } else if paragraphs[index].keepNext && index + 1 < paragraphs.length() {
      index += 1
      end += 1
      if (!paragraphs[index].keepNext || index + 1 == paragraphs.length()) &&
        !paragraphs[index].keepLines {
        break
      }
    } else {
      break
    }
  }
  Some(lines[end].1 + lines[end].0.height - lines[start].1)
}

///|
fn table_row_pending(
  cells : Array[(Int, Int, Array[(Line, Double, Line)], Double)],
  indices : Array[Int],
) -> Bool {
  for index, (_, _, lines, _) in cells {
    if indices[index] < lines.length() {
      return true
    }
  }
  false
}

///|
fn Table::fragment_required(
  self : Table,
  row : Int,
  cells : Array[(Int, Int, Array[(Line, Double, Line)], Double)],
  indices : Array[Int],
  origins : Array[Double],
  minimum : Double,
  full : Double,
  whole : Double,
) -> Double {
  let bottom = self.border_width(row + 1)
  let top = self.row_top_margin(row) + self.border_width(row)
  let mut required = full + 1
  for index, (_, column, lines, _) in cells {
    if indices[index] < lines.length() {
      let (normal, offset, first) = lines[indices[index]]
      let line = if indices[index] > 0 { first } else { normal }
      let kept = self.kept_paragraph_height(row, column, lines, indices[index])
      let height = if kept is Some(height) &&
        top + height + self.margins[row][column].bottom + bottom <= full {
        height
      } else {
        line.height
      }
      required = required.min(
        offset -
        origins[index] +
        height +
        self.margins[row][column].bottom +
        bottom,
      )
    }
  }
  if required > full && !table_row_pending(cells, indices) {
    required = (minimum + bottom).min(full)
  }
  required = required.max((minimum + bottom).min(full))
  if !self.splitRows[row] && whole <= full {
    required = required.max(whole)
  }
  required
}
