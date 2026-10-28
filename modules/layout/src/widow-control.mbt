///|
fn widow_height(
  lines : Array[(Int32, MeasuredLine)],
  start : Int32,
  count : Int32,
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
) -> Int32 {
  if !self.widowControl || measured.any(item => item.line.y < 0) {
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
  cache : ParagraphCache,
  probe : TextProbe,
  profile : Map[String, String],
) -> Map[Int32, Bool] raise @failure.Failure {
  let breaks : Map[Int32, Bool] = Map([])
  if !paragraph.widowControl || measured.any(item => item.line.y < 0) {
    return breaks
  }
  let lines : Array[(Int32, MeasuredLine)] = []
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
      bottom = self.wrapping_floor(page_index, bottom, height, square=false)
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
    let next_width = next.width - next.left - next.right
    if next_width != page.width - page.left - page.right {
      let next_lines = fn(offset : Int32) raise @failure.Failure {
        let lines = if self.wrapping.any(rect => rect.wrapping == "square") {
          self.square_lines(
            probe,
            paragraph,
            profile,
            offset,
            true,
            startPage=page_index + 1,
            startY=next.top,
          ).lines
        } else {
          cache.lines(probe, paragraph, profile, next_width, startOffset=offset)
        }
        lines
        .filter(item => !item.line.caretOnly)
        .mapi((index, item) => (index, item))
      }
      let following = next_lines(lines[start].1.line.start)
      let move_start = (
          count == 0 && widow_height(following, 0, 1, paragraph.line) <= full
        ) ||
        (
          count < 2 &&
          following.length() >= 2 &&
          widow_height(following, 0, 2, paragraph.line) <= full
        ) ||
        (
          count == 2 &&
          remaining == 3 &&
          widow_height(following, 0, following.length(), paragraph.line) <= full
        )
      if start == 0 && y > page.top && move_start {
        if self.pages.last().unwrap().lines.any(line => !line.caretOnly) ||
          !self.pages.last().unwrap().borders.is_empty() {
          self.next_page()
        } else {
          self.y = self.page.top
        }
        return breaks
      }
      while end > start + 2 {
        let tail = next_lines(lines[end].1.line.start)
        if tail.length() != 1 || widow_height(tail, 0, 1, paragraph.line) > full {
          break
        }
        end -= 1
      }
      if end > start {
        breaks[lines[end].0] = true
      }
      return breaks
    }
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
    guard self.pages.length() + breaks.length() < 1024 * self.columns.count else {
      @failure.reject("limit-exceeded", "Page budget exceeded")
    }
    breaks[lines[start].0] = true
  }
  breaks
}
