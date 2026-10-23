///|
fn table_scaled_extents(
  values : Array[Double],
  extent : Double,
) -> Array[Double] raise @failure.Failure {
  let total = values.fold(init=0L, (sum, value) => {
    sum + (value * 12700).round().to_int64()
  })
  let target = (extent * 12700).round().to_int64()
  let mut prefix = 0L
  let mut previous = 0L
  values.map(value => {
    prefix += (value * 12700).round().to_int64()
    let next = target * prefix / total
    let size = next - previous
    guard size > 0 else {
      @failure.reject(
        "invalid-transform", "Table grid dimensions must remain positive",
      )
    }
    previous = next
    size.to_double() / 12700
  })
}

///|
fn DrawingTable::resized(
  self : DrawingTable,
  width : Double,
  height : Double,
) -> DrawingTable raise @failure.Failure {
  let widths = table_scaled_extents(self.widths, width)
  let heights = table_scaled_extents(self.rows.map(row => row.height), height)
  let table = {
    ..self,
    widths,
    rows: self.rows.mapi((r, row) => { ..row, height: heights[r], }),
  }
  for row in table.rows {
    for column, cell in row.cells {
      guard !cell.owner() ||
        cell.body.left + cell.body.right < table.width(column, cell) else {
        @failure.reject(
          "invalid-transform", "Table cell margins leave no text width",
        )
      }
    }
  }
  table
}

///|
fn table_transform_changes(
  object : Object,
  geometry : Geometry,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let before = object.table.unwrap()
  let table = before.resized(geometry.width, geometry.height)
  let transform = object.source.child("xfrm", uri=presentation_uri).unwrap()
  let changes = transform.pose_changes(object.geometry.unwrap(), geometry)
  for
    (node, values) in [
      (transform.child("off").unwrap(), [("x", geometry.x), ("y", geometry.y)]),
      (
        transform.child("ext").unwrap(),
        [("cx", geometry.width), ("cy", geometry.height)],
      ),
    ] {
    for (name, value) in values {
      let value = (value * 12700).round().to_int64().to_string()
      if node.node.attribute(name) != Some(value) {
        changes.push(attribute_change(node, name, value))
      }
    }
  }
  let source = object.source
    .child("graphic")
    .unwrap()
    .child("graphicData")
    .unwrap()
    .child("tbl")
    .unwrap()
  let grid = source.child("tblGrid").unwrap()
  let columns = grid.tree.all(grid.node.id, "gridCol")
  for column, width in table.widths {
    let value = (width * 12700).round().to_int64().to_string()
    if columns[column].attribute("w") != Some(value) {
      changes.push(
        attribute_change(
          { tree: grid.tree, node: columns[column], },
          "w",
          value,
        ),
      )
    }
  }
  for row in table.rows {
    let value = (row.height * 12700).round().to_int64().to_string()
    if row.source.node.attribute("h") != Some(value) {
      changes.push(attribute_change(row.source, "h", value))
    }
  }
  changes
}
