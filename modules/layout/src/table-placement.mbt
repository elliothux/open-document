///|
fn Pagination::prepare_table(
  self : Pagination,
  table : Table,
  cache : ParagraphCache,
  probe : TextProbe,
  profile : Map[String, String],
  additive : Bool,
) -> Unit raise @failure.Failure {
  if table.rows[0]
    .get(0)
    .bind(cell => cell.get(0))
    .map(p => p.pageBreakBefore)
    .unwrap_or(false) &&
    (
      self.pages.last().unwrap().lines.any(line => !line.caretOnly) ||
      !self.pages.last().unwrap().borders.is_empty()
    ) {
    self.sheet_break()
  }
  if self.y >= self.page.height - self.page.bottom {
    self.next_page()
  }
  let mut fitted = table.fit_widths(
    probe,
    profile,
    self.page.width - self.page.left - self.page.right,
  )
  if !self.columns.custom.is_empty() {
    let required = fitted.start_height(
      cache,
      probe,
      self.page,
      profile,
      additive,
    )
    if self.y > self.page.top &&
      self.y + required > self.page.height - self.page.bottom {
      self.next_page()
      fitted = table.fit_widths(
        probe,
        profile,
        self.page.width - self.page.left - self.page.right,
      )
    }
  }
  ignore(fitted.left(self.page))
  self.tables[table.id] = fitted
  self.active_table = Some(table.id)
}

///|
fn Pagination::retain_block(
  self : Pagination,
  block : BodyBlock,
  before : PagePosition,
  after : PagePosition,
  cache : ParagraphCache,
  probe : TextProbe,
  profile : Map[String, String],
) -> Unit raise @failure.Failure {
  if block is TableStart(table) {
    let page = self.page_at(after.page)
    self.tables[table.id] = table.fit_widths(
      probe,
      profile,
      page.width - page.left - page.right,
    )
  }
  block.retain(cache, self.page_at(before.page), self.tables)
}
