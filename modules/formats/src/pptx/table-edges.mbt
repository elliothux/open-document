///|
fn DrawingTable::edge(
  self : DrawingTable,
  row : Int,
  column : Int,
  vertical : Bool,
) -> (String, Double) {
  let before = if vertical {
    if column > 0 {
      Some(self.owners[row][column - 1])
    } else {
      None
    }
  } else if row > 0 {
    Some(self.owners[row - 1][column])
  } else {
    None
  }
  let after = if vertical {
    if column < self.widths.length() {
      Some(self.owners[row][column])
    } else {
      None
    }
  } else if row < self.rows.length() {
    Some(self.owners[row][column])
  } else {
    None
  }
  if before == after {
    return ("", 0)
  }
  let mut result = ("", 0.0)
  let mut priority = -1
  for
    (owner, side) in [
      (before, if vertical { 2 } else { 3 }),
      (after, if vertical { 0 } else { 1 }),
    ] {
    if owner is Some((r, c)) {
      let cell = self.rows[r].cells[c]
      let value = cell.borders[side]
      let rank = cell.border_priorities[side]
      if !value.0.is_empty() &&
        (
          result.0.is_empty() ||
          rank > priority ||
          (rank == priority && value.1 >= result.1)
        ) {
        result = value
        priority = rank
      }
    }
  }
  result
}

///|
fn DrawingTable::cell_borders(
  self : DrawingTable,
  row : Int,
  column : Int,
) -> Array[(String, Double)] {
  let cell = self.rows[row].cells[column]
  let edges : Array[(String, Double)] = []
  for r in row..<(row + cell.row_span) {
    edges.push(self.edge(r, column, true))
    edges.push(self.edge(r, column + cell.column_span, true))
  }
  for c in column..<(column + cell.column_span) {
    edges.push(self.edge(row, c, false))
    edges.push(self.edge(row + cell.row_span, c, false))
  }
  edges
}

///|
fn DrawingTable::paint_edges(
  self : DrawingTable,
) -> Array[@layout.PositionedPrimitive] {
  let output : Array[@layout.PositionedPrimitive] = []
  let mut y = 0.0
  for row in 0..<=self.rows.length() {
    let mut x = 0.0
    for column in 0..<=self.widths.length() {
      for vertical in [false, true] {
        if (vertical && row == self.rows.length()) ||
          (!vertical && column == self.widths.length()) {
          continue
        }
        let (color, width) = self.edge(row, column, vertical)
        if color.is_empty() {
          continue
        }
        let (end_x, end_y) = if vertical {
          (x, y + self.rows[row].height)
        } else {
          (x + self.widths[column], y)
        }
        output.push(
          Path([Move(x, y), Line(end_x, end_y)], "", color, width, {
            fillAlpha: 1,
            strokeAlpha: 1,
            dash: [],
            cap: 0,
            join: 0,
            miter: 8,
          }),
        )
      }
      if column < self.widths.length() {
        x += self.widths[column]
      }
    }
    if row < self.rows.length() {
      y += self.rows[row].height
    }
  }
  output
}
