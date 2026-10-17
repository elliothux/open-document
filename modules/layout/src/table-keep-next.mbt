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
  let whole = heights.fold(init=0.0, (sum, height) => sum + height) +
    self.border_width(end + 1)
  if end > 0 || self.exactHeights[0] || !self.splitRows[0] {
    return whole
  }
  self.fragment_required(
    0,
    cells,
    Array::make(cells.length(), 0),
    Array::make(cells.length(), 0.0),
    self.row_minimum_height(0),
    page.height - page.top - page.bottom,
    whole,
  )
}
