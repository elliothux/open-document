///|
priv struct SectionContinuation {
  frame : PageFrame
  page : PageSetup
  y : Double
  after : Double
  gap : Double
}

///|
fn Pagination::section_continuation(self : Pagination) -> SectionContinuation? {
  let index = self.pages.length() - 1
  if self.notePages.keys().any(frame => frame / self.columns.count == index) ||
    self.noteCursor < self.notePending.length() {
    return None
  }
  let frame = self.pages[index]
  let y = frame.lines.fold(init=self.y, (bottom, line) => {
    bottom.max(line.y + line.height)
  })
  let y = frame.cellAreas.fold(init=y, (bottom, area) => {
    bottom.max(area.y + area.height)
  })
  let page = if index == 0 && self.continuation is Some(previous) {
    previous.page
  } else {
    self.sheet_setup(index)
  }
  Some({ frame, page, y, after: self.after, gap: self.gap, })
}
