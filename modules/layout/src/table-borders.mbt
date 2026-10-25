///|
/// Returns the total line-and-gap width, in points.
pub fn BorderStyle::extent(self : BorderStyle) -> Double {
  self.width * (if self.style == "double" { 3.0 } else { 1.0 })
}

///|
fn PageFrame::paint_table_border(
  self : PageFrame,
  rect : Border,
  edge : BorderStyle,
) -> Unit raise @failure.Failure {
  if edge.width <= 0 {
    return
  }
  guard self.borders.length() < 65536 else {
    @failure.reject("limit-exceeded", "Table borders exceed65536 page segments")
  }
  if edge.style == "double" {
    guard self.borders.length() <= 65534 else {
      @failure.reject(
        "limit-exceeded", "Double table borders exceed65536 page segments",
      )
    }
    for offset in [-edge.width, edge.width] {
      self.borders.push({
        rect: {
          ..rect,
          x: rect.x + (if rect.width == 0 { offset } else { 0.0 }),
          y: rect.y + (if rect.width == 0 { 0.0 } else { offset }),
        },
        color: edge.color,
        width: edge.width,
      })
    }
    return
  }
  if edge.style == "single" {
    self.borders.push({ rect, color: edge.color, width: edge.width, })
    return
  }
  let vertical = rect.width == 0
  let length = if vertical { rect.height } else { rect.width }
  // LibreOffice GetLineDashing supplies line/gap ratios; retain the native width scale.
  let pattern : Array[Double] = match edge.style {
    "dashed" => [16, 5]
    "dotted" => [1, 2]
    "dashSmallGap" => [6, 2]
    "dotDash" => [16, 5, 5, 5]
    "dotDotDash" => [16, 5, 5, 5, 5, 5]
    _ =>
      @failure.reject("unsupported-layout", "Unsupported table border pattern")
  }
  let period = pattern.fold(init=0.0, (sum, value) => sum + value) * edge.width
  let cycles = (length / period).ceil().to_int()
  guard cycles <= 8192 else {
    @failure.reject(
      "limit-exceeded", "Table border pattern exceeds the segment budget",
    )
  }
  let spans : Array[(Double, Double)] = []
  for cycle in 0..<cycles {
    let mut offset = cycle.to_double() * period
    for index = 0
        index < pattern.length() && offset < length
        index = index + 2 {
      guard spans.length() < 8192 &&
        spans.length() < 65536 - self.borders.length() else {
        @failure.reject(
          "limit-exceeded", "Table border pattern exceeds the segment budget",
        )
      }
      let size = pattern[index] * edge.width
      spans.push((offset, size.min(length - offset)))
      offset += size + pattern[index + 1] * edge.width
    }
  }
  for (offset, size) in spans {
    self.borders.push({
      rect: {
        x: rect.x + (if vertical { 0.0 } else { offset }),
        y: rect.y + (if vertical { offset } else { 0.0 }),
        width: if vertical {
          0.0
        } else {
          size
        },
        height: if vertical {
          size
        } else {
          0.0
        },
      },
      color: edge.color,
      width: edge.width,
    })
  }
}

///|
pub fn Table::border_width(self : Table, row : Int) -> Double {
  self.borders.horizontal[row].fold(init=0.0, (width, edge) => {
    width.max(edge.extent())
  })
}

///|
pub fn Table::cell_insets(self : Table, row : Int, cell : Int) -> CellMargins {
  let start = self.columnSpans[row][:cell].fold(init=0, (sum, span) => {
    sum + span
  })
  let end = start + self.columnSpans[row][cell]
  let last = row + self.rowSpans[row][cell].max(1)
  let left = self.borders.vertical[row:last].fold(init=0.0, (width, edges) => {
    width.max(edges[start].extent() / 2)
  })
  let right = self.borders.vertical[row:last].fold(init=0.0, (width, edges) => {
    width.max(edges[end].extent() / 2)
  })
  {
    ..self.margins[row][cell],
    left: self.margins[row][cell].left.max(left),
    right: self.margins[row][cell].right.max(right),
  }
}

///|
pub fn Table::row_minimum_height(self : Table, row : Int) -> Double {
  let top = self.margins[row].fold(init=0.0, (v, m) => v.max(m.top))
  let bottom = self.margins[row].fold(init=0.0, (v, m) => v.max(m.bottom))
  let border = self.border_width(row)
  // ONLYOFFICE TableRecalculate adds margins; exact heights include the top border.
  if self.exactHeights[row] {
    (self.heights[row] + top + bottom).max(border).max(0.05)
  } else {
    (self.heights[row] + border).max(top + bottom + border)
  }
}

///|
fn Table::paint_borders(
  self : Table,
  page : PageFrame,
  first : Int,
  last : Int,
  x : Double,
  y : Double,
  heights : Array[Double],
) -> Unit raise @failure.Failure {
  let previous = if first > 0 {
    self.rows[first - 1].flatten().map(paragraph => paragraph.id)
  } else {
    []
  }
  let shared_top = page.cellAreas.any(area => {
    (area.y + area.height - y).abs() < 0.000001 &&
    area.paragraphs.any(id => previous.contains(id))
  })
  let mut top = y
  for row in first..<=(last + 1) {
    let mut left = x
    for column, width in self.widths {
      let edge = self.borders.horizontal[row][column]
      if edge.width > 0 && (row != first || !shared_top) {
        page.paint_table_border({ x: left, y: top, width, height: 0, }, edge)
      }
      left += width
    }
    if row <= last {
      top += heights[row - first]
    }
  }
  let mut top = y
  for row in first..<=last {
    let mut left = x
    for column in 0..<=self.widths.length() {
      let edge = self.borders.vertical[row][column]
      if edge.width > 0 {
        page.paint_table_border(
          { x: left, y: top, width: 0, height: heights[row - first], },
          edge,
        )
      }
      if column < self.widths.length() {
        left += self.widths[column]
      }
    }
    top += heights[row - first]
  }
}
