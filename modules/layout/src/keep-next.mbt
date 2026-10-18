///|
fn paragraph_has_break(paragraph : Paragraph) -> Bool {
  paragraph.spans.any(span => {
    span.text.contains("\u000b") || span.text.contains("\u000c")
  })
}

///|
fn keep_next_blocks(blocks : Array[BodyBlock]) -> Array[BodyBlock] {
  let result = []
  let mut index = 0
  while index < blocks.length() {
    let start = index
    let paragraphs : Array[Paragraph] = []
    while index < blocks.length() && blocks[index] is BodyParagraph(paragraph) {
      if index > start &&
        (paragraph.pageBreakBefore || paragraph_has_break(paragraph)) {
        break
      }
      paragraphs.push(paragraph)
      index += 1
      if !paragraph.keepNext || paragraph_has_break(paragraph) {
        break
      }
    }
    let following = if paragraphs.last() is Some(last) &&
      last.keepNext &&
      !paragraph_has_break(last) &&
      blocks.get(index) is Some(TableStart(table)) &&
      !table.rows[0]
      .get(0)
      .bind(cell => cell.get(0))
      .map(p => p.pageBreakBefore)
      .unwrap_or(false) {
      Some(table)
    } else {
      None
    }
    if paragraphs.length() > 1 || following is Some(_) {
      result.push(KeptParagraphs(paragraphs, following))
    } else {
      result.push(blocks[start])
      index = start + 1
    }
  }
  result
}

///|
fn Pagination::kept_paragraphs(
  self : Pagination,
  cache : ParagraphCache,
  probe : TextProbe,
  paragraphs : Array[Paragraph],
  following : Table?,
  profile : Map[String, String],
  images : Images,
  additive : Bool,
) -> Unit raise @failure.Failure {
  let heights = []
  let gaps = []
  for index, paragraph in paragraphs {
    paragraph.validate_spacing(self.page.height)
    let lines = cache.lines(
      probe,
      paragraph,
      profile,
      self.page.width - self.page.left - self.page.right,
    )
    let mut height = 0.0
    let minimum = paragraph.kept_start_count(lines, self.page)
    let mut count = 0
    let mut gap = 0.0
    let mut first = true
    for measured in lines {
      if measured.line.caretOnly {
        continue
      }
      height += measured.spaced(paragraph.line, first).height
      count += 1
      gap = paragraph.line.gap(measured.textHeight)
      first = false
      if index == paragraphs.length() - 1 &&
        following is None &&
        !paragraph.keepLines &&
        count >= minimum {
        break
      }
    }
    heights.push(height)
    gaps.push(gap)
  }
  let required = heights.copy()
  if following is Some(table) {
    let last = paragraphs.length() - 1
    required[last] += gaps[last] +
      paragraphs[last].after +
      table.start_height(cache, probe, self.page, profile, additive)
  }
  for offset in 1..<paragraphs.length() {
    let index = paragraphs.length() - offset - 1
    let spacing = if additive {
      paragraphs[index].after + paragraphs[index + 1].before
    } else {
      paragraphs[index].after.max(paragraphs[index + 1].before)
    }
    required[index] += gaps[index] + spacing + required[index + 1]
  }
  for index, paragraph in paragraphs {
    let limit = self.page.height - self.page.bottom
    let next = self.page_at(self.pages.length())
    let full = next.height - next.top - next.bottom
    let spacing = if additive {
      self.after + paragraph.before
    } else {
      self.after.max(paragraph.before)
    }
    if required[index] <= full &&
      self.y + self.gap + spacing + required[index] > limit &&
      (
        self.pages.last().unwrap().lines.any(line => !line.caretOnly) ||
        !self.pages.last().unwrap().borders.is_empty()
      ) {
      self.next_page()
    }
    let capacity = self.page.height - self.page.top - self.page.bottom
    let paragraph = if self.y == self.page.top &&
      required[index] <= capacity &&
      paragraph.before + required[index] > capacity {
      { ..paragraph, before: 0, }
    } else {
      paragraph
    }
    self.paragraph(cache, probe, paragraph, profile, images, additive)
  }
}
