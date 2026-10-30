///|
fn Table::start_height(
  self : Table,
  cache : ParagraphCache,
  probe : TextProbe,
  page : PageSetup,
  profile : Map[String, String],
  additive : Bool,
) -> Double raise @failure.Failure {
  let end = self.row_group_end(0)
  let (heights, cells) = self.measure_rows(
    cache, probe, page, 0, end, profile, additive,
  )
  let group = heights.fold(init=0.0, (sum, height) => sum + height) +
    self.border_width(end + 1)
  if end > 0 && group <= page.height - page.top - page.bottom {
    return group
  }
  let whole = heights[0] + self.border_width(1)
  if self.exactHeights[0] ||
    !self.splitRows[0] ||
    self.nestedTables.any(child => child.row <= end) {
    return whole
  }
  self.fragment_required(
    0,
    cells.filter(cell => cell.0 == 0),
    Array::make(cells.length(), 0),
    Array::make(cells.length(), 0.0),
    self.row_minimum_height(0),
    page.height - page.top - page.bottom,
    whole,
  )
}
