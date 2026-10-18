///|
fn Session::resize_table_axis(
  self : Session,
  rows : Bool,
  value : Double,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  guard !value.is_nan() && !value.is_inf() && value >= 0.1 && value <= 14400 else {
    @failure.reject(
      "invalid-operation", "Table dimensions must be within 0.1 and 14400 points",
    )
  }
  guard self.selection.objects.length() == 1 else {
    @failure.reject(
      "invalid-operation", "Select one table to resize its rows or columns",
    )
  }
  let original = self.current()
  let object = original.object(self.selection.object)
  guard object.table is Some(table) else {
    @failure.reject("protected-content", "Select an editable table")
  }
  let (_, _, reason) = self.table_position(object, self.selection)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let range = table.range(self.selection)
  let first = if rows { range.top } else { range.left }
  let last = if rows { range.bottom } else { range.right }
  let size = (value * 12700).round().to_int64()
  let changes : Array[@xml.SourceChange] = []
  let values = if rows {
    table.rows.map(row => row.height)
  } else {
    table.widths
  }
  let grid = object.source
    .child("graphic")
    .unwrap()
    .child("graphicData")
    .unwrap()
    .child("tbl")
    .unwrap()
    .child("tblGrid")
    .unwrap()
  let columns = grid.tree.all(grid.node.id, "gridCol")
  let mut extent = 0L
  for index, current in values {
    let before = (current * 12700).round().to_int64()
    let after = if index >= first && index <= last { size } else { before }
    extent += after
    if after != before {
      changes.push(
        attribute_change(
          if rows {
            table.rows[index].source
          } else {
            { tree: grid.tree, node: columns[index], }
          },
          if rows {
            "h"
          } else {
            "w"
          },
          after.to_string(),
        ),
      )
    }
  }
  guard extent <= 182880000L else {
    @failure.reject("limit-exceeded", "Table extent exceeds 14400 points")
  }
  if changes.is_empty() {
    return self.query()
  }
  let transform = object.source.child("xfrm", uri=presentation_uri).unwrap()
  changes.push(
    attribute_change(
      transform.child("ext").unwrap(),
      if rows {
        "cy"
      } else {
        "cx"
      },
      extent.to_string(),
    ),
  )
  let (candidate, edit) = self.prepare_table(
    original,
    changes,
    object.id,
    probe,
    profile,
  )
  if candidate.tree.document.source() == original.tree.document.source() {
    return self.query()
  }
  self.commit(candidate, edit, self.selection)
  self.query()
}
