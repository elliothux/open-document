///|
pub fn Table::border_width(self : Table, row : Int) -> Double {
  self.borders.horizontal[row].fold(init=0.0, (width, edge) => {
    width.max(edge.width)
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
    width.max(edges[start].width / 2)
  })
  let right = self.borders.vertical[row:last].fold(init=0.0, (width, edges) => {
    width.max(edges[end].width / 2)
  })
  {
    ..self.margins[row][cell],
    left: self.margins[row][cell].left.max(left),
    right: self.margins[row][cell].right.max(right),
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
) -> Unit {
  let mut top = y
  for row in first..<=(last + 1) {
    let mut left = x
    for column, width in self.widths {
      let edge = self.borders.horizontal[row][column]
      if edge.width > 0 {
        page.borders.push({
          rect: { x: left, y: top, width, height: 0, },
          color: edge.color,
          width: edge.width,
        })
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
        page.borders.push({
          rect: { x: left, y: top, width: 0, height: heights[row - first], },
          color: edge.color,
          width: edge.width,
        })
      }
      if column < self.widths.length() {
        left += self.widths[column]
      }
    }
    top += heights[row - first]
  }
}
