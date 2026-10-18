///|
fn Object::format_targets(
  self : Object,
  selection : Selection,
) -> Array[(Object, Selection)] raise @failure.Failure {
  guard self.table is Some(table) else { return [(self, selection)] }
  let range = table.format_range(selection)
  let whole = selection.mode == "object" || range.multiple()
  let targets : Array[(Object, Selection)] = []
  for r in range.top..<=range.bottom {
    for c in range.left..<=range.right {
      let cell = table.rows[r].cells[c]
      if !cell.owner() {
        continue
      }
      let selected = if whole {
        { ..selection, mode: "object", anchor: 0, focus: 0, }
      } else {
        let offset = table.cell_offset(r, c)
        {
          ..selection,
          anchor: selection.anchor - offset,
          focus: selection.focus - offset,
        }
      }
      targets.push((self.table_cell(cell), selected))
    }
  }
  targets
}
