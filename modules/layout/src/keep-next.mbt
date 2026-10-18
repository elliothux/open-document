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
fn kept_required(
  cache : ParagraphCache,
  probe : TextProbe,
  paragraphs : Array[Paragraph],
  following : Table?,
  page : PageSetup,
  profile : Map[String, String],
  additive : Bool,
) -> Array[Double] raise @failure.Failure {
  let heights = []
  let gaps = []
  for index, paragraph in paragraphs {
    paragraph.validate_spacing(page.height)
    let lines = cache.lines(
      probe,
      paragraph,
      profile,
      page.width - page.left - page.right,
    )
    let mut height = 0.0
    let minimum = paragraph.kept_start_count(lines, page)
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
    let table = table.fit_widths(
      probe,
      profile,
      page.width - page.left - page.right,
    )
    let last = paragraphs.length() - 1
    required[last] += gaps[last] +
      paragraphs[last].after +
      table.start_height(cache, probe, page, profile, additive)
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
  required
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
  let measured : Map[String, Array[Double]] = Map([])
  let required_at = fn(page : PageSetup) raise @failure.Failure {
    let key = Json::array([
      Json(page.width - page.left - page.right),
      Json(page.height),
      Json(page.top + page.bottom),
    ]).stringify()
    if measured.get(key) is Some(values) {
      return values
    }
    let values = kept_required(
      cache, probe, paragraphs, following, page, profile, additive,
    )
    if measured.length() < 32 {
      measured[key] = values
    }
    values
  }
  for index, paragraph in paragraphs {
    let required = required_at(self.page)[index]
    let limit = self.page.height - self.page.bottom
    let next = self.page_at(self.pages.length())
    let full = next.height - next.top - next.bottom
    let spacing = if additive {
      self.after + paragraph.before
    } else {
      self.after.max(paragraph.before)
    }
    if self.y + self.gap + spacing + required > limit &&
      (
        self.pages.last().unwrap().lines.any(line => !line.caretOnly) ||
        !self.pages.last().unwrap().borders.is_empty()
      ) {
      let fits_next = try required_at(next)[index] <= full catch {
        @failure.Failure(code="layout-overflow" | "invalid-style", ..) => false
        error => raise error
      }
      if fits_next {
        self.next_page()
      }
    }
    let required = required_at(self.page)[index]
    let capacity = self.page.height - self.page.top - self.page.bottom
    let paragraph = if self.y == self.page.top &&
      required <= capacity &&
      paragraph.before + required > capacity {
      { ..paragraph, before: 0, }
    } else {
      paragraph
    }
    self.paragraph(cache, probe, paragraph, profile, images, additive)
  }
}
