///|
fn Session::prepare_fill_sparklines(
  self : Session,
  plan : CellEditPlan,
  index : Int,
  source : Range,
  target : Range,
) -> Bool raise @failure.Failure {
  let original = self.sheets[index].sparklines
  let seeds = original.items.filter(item => source.contains(item.cell))
  let items = original.items.filter(item => !target.contains(item.cell))
  let vertical = source.left == target.left && source.right == target.right
  let stride = if vertical {
    source.bottom - source.top + 1
  } else {
    source.right - source.left + 1
  }
  let first = if vertical { target.top } else { target.left }
  let last = if vertical { target.bottom } else { target.right }
  let origin = if vertical { source.top } else { source.left }
  let start = first - ((first - origin) % stride + stride) % stride
  for axis = start; axis <= last; axis = axis + stride {
    let rows = if vertical { axis - origin } else { 0 }
    let columns = if vertical { 0 } else { axis - origin }
    for seed in seeds {
      let cell : Address = {
        row: seed.cell.row + rows,
        column: seed.cell.column + columns,
      }
      if !target.contains(cell) {
        continue
      }
      guard items.length() < 256 else {
        @failure.reject("limit-exceeded", "Filled sparklines exceed 256")
      }
      guard !plan.sheets[index].merges.any(range => range.contains(cell)) else {
        @failure.reject(
          "protected-content", "Sparkline locations require an unmerged cell",
        )
      }
      items.push({
        ..seed,
        cell,
        source: seed.source.map(range => range.sparkline_offset(rows, columns)),
      })
    }
  }
  if items.length() == original.items.length() &&
    items.all(item => original.items.contains(item)) {
    return false
  }
  items.sort_by((a, b) => {
    if a.cell.row == b.cell.row {
      a.cell.column.compare(b.cell.column)
    } else {
      a.cell.row.compare(b.cell.row)
    }
  })
  // Cell preparation can merge over old destinations that this fill replaces.
  let sheet = { ..plan.sheets[index], sparklines: original, }
  let (document, edit) = sheet.document.edit_source(
    sheet.sparkline_changes(items),
  )
  plan.edits.push((sheet.id, edit))
  plan.sheets[index] = Sheet::read(
    sheet.id,
    sheet.name,
    sheet.state,
    document,
    self.strings,
    plan.styles.length(),
  )
  true
}
