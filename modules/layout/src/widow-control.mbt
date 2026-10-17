///|
fn widow_height(
  lines : Array[(Int, MeasuredLine)],
  start : Int,
  count : Int,
  spacing : LineSpacing,
) -> Double {
  let mut height = 0.0
  for index in start..<(start + count) {
    height += lines[index].1.spaced(spacing, index == start).height
  }
  height
}

///|
fn Paragraph::kept_start_count(
  self : Paragraph,
  measured : Array[MeasuredLine],
  page : PageSetup,
) -> Int {
  if !self.widowControl || measured.any(item => item.line.y == -1) {
    return 1
  }
  let lines = measured.filter(item => !item.line.caretOnly)
  if lines.length() < 2 {
    return 1
  }
  let height = lines[0].spaced(self.line, true).height +
    lines[1].spaced(self.line, false).height
  let full = page.height - page.top - page.bottom
  if height > full {
    return 1
  }
  if lines.length() == 3 &&
    height + lines[2].spaced(self.line, false).height <= full {
    3
  } else {
    2
  }
}

///|
fn Pagination::widow_breaks(
  self : Pagination,
  paragraph : Paragraph,
  measured : Array[MeasuredLine],
) -> Map[Int, Bool] raise @failure.Failure {
  let breaks : Map[Int, Bool] = Map([])
  if !paragraph.widowControl || measured.any(item => item.line.y == -1) {
    return breaks
  }
  let lines : Array[(Int, MeasuredLine)] = []
  for index, line in measured {
    if !line.line.caretOnly {
      lines.push((index, line))
    }
  }
  let mut page_index = self.pages.length() - 1
  let mut start = 0
  let mut y = self.y
  while start < lines.length() {
    let page = self.page_at(page_index)
    let limit = page.height - page.bottom
    let next = self.page_at(page_index + 1)
    let full = next.height - next.top - next.bottom
    let mut end = start
    let mut bottom = y
    while end < lines.length() {
      let height = lines[end].1.spaced(paragraph.line, end == start).height
      if bottom + height > limit {
        break
      }
      bottom += height
      end += 1
    }
    if end == lines.length() {
      break
    }
    let count = end - start
    let remaining = lines.length() - start
    let move_start = (
        count == 0 && widow_height(lines, start, 1, paragraph.line) <= full
      ) ||
      (
        count < 2 &&
        remaining >= 2 &&
        widow_height(lines, start, 2, paragraph.line) <= full
      ) ||
      (
        count == 2 &&
        remaining == 3 &&
        widow_height(lines, start, 3, paragraph.line) <= full
      )
    if start == 0 && y > page.top && move_start {
      if self.pages.last().unwrap().lines.any(line => !line.caretOnly) ||
        !self.pages.last().unwrap().borders.is_empty() {
        self.next_page()
      } else {
        self.y = self.page.top
      }
      y = self.page.top
      page_index = self.pages.length() - 1
      continue
    }
    if lines.length() - end == 1 &&
      count >= 3 &&
      widow_height(lines, end - 1, 2, paragraph.line) <= full {
      end -= 1
    }
    // A page too short for one line follows the existing layout-overflow path.
    if end == start {
      return breaks
    }
    start = end
    page_index += 1
    y = self.page_at(page_index).top
    guard self.pages.length() + breaks.length() < 1024 else {
      @failure.reject("limit-exceeded", "Page budget exceeded")
    }
    breaks[lines[start].0] = true
  }
  breaks
}
