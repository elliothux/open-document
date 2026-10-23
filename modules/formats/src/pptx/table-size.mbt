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
  let (_, _, reason) = self.table_position(
    object,
    self.selection,
    allow_grouped=true,
  )
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let range = table.range(self.selection)
  let first = if rows { range.top } else { range.left }
  let last = if rows { range.bottom } else { range.right }
  let parent = object.source.parent_matrix()
  let scale = if rows {
    (parent.c * parent.c + parent.d * parent.d).sqrt()
  } else {
    (parent.a * parent.a + parent.b * parent.b).sqrt()
  }
  let size = (value / scale * 12700).round().to_int64()
  guard size > 0 else {
    @failure.reject(
      "invalid-transform", "Native table dimensions must remain positive",
    )
  }
  let changes : Array[@xml.SourceChange] = []
  let count = if rows { table.rows.length() } else { table.widths.length() }
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
  for index in 0..<count {
    let node = if rows {
      table.rows[index].source
    } else {
      { tree: grid.tree, node: columns[index], }
    }
    let key = if rows { "h" } else { "w" }
    let before = number(node.node.attribute(key).unwrap(), 1, 182880000).to_int64()
    let displayed = if rows {
      table.rows[index].height
    } else {
      table.widths[index]
    }
    // Reapplying a displayed value must not reverse its rounded group geometry.
    let after = if index >= first && index <= last && value != displayed {
      size
    } else {
      before
    }
    extent += after
    if after != before {
      changes.push(attribute_change(node, key, after.to_string()))
    }
  }
  guard extent <= 182880000L && extent.to_double() * scale <= 182880000.5 else {
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
  self.commit(candidate, edit, self.selection, probe~, profile~)
  self.query()
}
