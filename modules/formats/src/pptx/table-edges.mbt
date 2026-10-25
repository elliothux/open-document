///|
fn DrawingTable::edge_paint(
  self : DrawingTable,
  row : Int,
  column : Int,
  vertical : Bool,
) -> ((String, Double, String, Double), (Ref, Ref?)?) {
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
    return (("", 0, "solid", 1), None)
  }
  let mut result = ("", 0.0, "solid", 1.0)
  let mut priority = -1
  let mut source : (Ref, Ref?)? = None
  let reverse = vertical && self.rtl
  for
    (owner, side) in [
      (if reverse { after } else { before }, if vertical { 2 } else { 3 }),
      (if reverse { before } else { after }, if vertical { 0 } else { 1 }),
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
        source = cell.border_sources[side]
        priority = rank
      }
    }
  }
  (result, source)
}

///|
fn DrawingTable::edge(
  self : DrawingTable,
  row : Int,
  column : Int,
  vertical : Bool,
) -> (String, Double, String, Double) {
  self.edge_paint(row, column, vertical).0
}

///|
fn DrawingTable::cell_borders(
  self : DrawingTable,
  row : Int,
  column : Int,
) -> Array[(String, Double, String, Double)] {
  let cell = self.rows[row].cells[column]
  let edges : Array[(String, Double, String, Double)] = []
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
) -> Array[@layout.PositionedPrimitive] raise @failure.Failure {
  let output : Array[@layout.PositionedPrimitive] = []
  let mut y = 0.0
  for row in 0..<=self.rows.length() {
    for column in 0..<=self.widths.length() {
      let x = self.column_edge(column)
      for vertical in [false, true] {
        if (vertical && row == self.rows.length()) ||
          (!vertical && column == self.widths.length()) {
          continue
        }
        let (color, width, dash, alpha) = self.edge(row, column, vertical)
        if color.is_empty() {
          continue
        }
        let (end_x, end_y) = if vertical {
          (x, y + self.rows[row].height)
        } else {
          (self.column_edge(column + 1), y)
        }
        output.push(
          Path([Move(x, y), Line(end_x, end_y)], "", color, width, {
            fillAlpha: 1,
            strokeAlpha: alpha,
            dash: dash_pattern(dash).map(value => value * width),
            cap: 0,
            join: 0,
            miter: 8,
          }),
        )
      }
    }
    if row < self.rows.length() {
      y += self.rows[row].height
    }
  }
  output
}
