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
  wrapping : (Pagination, Int, Double)?,
) -> Array[Double] raise @failure.Failure {
  let heights = []
  let gaps = []
  let mut top = wrapping.map(context => context.2).unwrap_or(0)
  for index, paragraph in paragraphs {
    paragraph.validate_spacing(page.height)
    let plan = wrapping.map(context => {
      context.0.square_lines(
        probe,
        paragraph,
        profile,
        0,
        true,
        startPage=context.1,
        startY=top,
      )
    })
    let lines = if plan is Some(plan) {
      plan.lines
    } else {
      cache.lines(
        probe,
        paragraph,
        profile,
        page.width - page.left - page.right,
      )
    }
    let mut height = 0.0
    let minimum = paragraph.kept_start_count(lines, page)
    let mut count = 0
    let mut gap = 0.0
    let mut first = true
    for row, measured in lines {
      if measured.line.caretOnly {
        continue
      }
      let row_height = measured.spaced(paragraph.line, first).height
      height = if plan is Some(plan) {
        let (target, y, _) = plan.positions[row]
        if target == wrapping.unwrap().1 {
          y - top + row_height
        } else {
          (page.height - top).max(0) + row_height
        }
      } else {
        height + row_height
      }
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
    top += height + gap
    if paragraphs.get(index + 1) is Some(next) {
      top += if additive {
        paragraph.after + next.before
      } else {
        paragraph.after.max(next.before)
      }
    }
  }
  let required = heights.copy()
  if following is Some(table) {
    let table = table.fit_widths(
      probe,
      profile,
      page.width - page.left - page.right,
    )
    let last = paragraphs.length() - 1
    let table_height = table.start_height(cache, probe, page, profile, additive)
    let table_top = top + paragraphs[last].after
    let excluded = wrapping
      .map(context => {
        context.0.wrapping_floor(context.1, table_top, table_height) - table_top
      })
      .unwrap_or(0)
    required[last] += gaps[last] +
      paragraphs[last].after +
      excluded +
      table_height
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
  let required_at = fn(
    page : PageSetup,
    page_index : Int,
    index : Int,
    y : Double,
  ) raise @failure.Failure {
    let square = self.wrapping.any(rect => rect.wrapping == "square")
    let start = if square { index } else { 0 }
    let key = Json::array([
      Json(page.width - page.left - page.right),
      Json(page.height),
      Json(page.top + page.bottom),
      Json(start),
      if square {
        Json::array([Json(page_index), Json(y), Json(self.wrapping)])
      } else {
        Json::null()
      },
    ]).stringify()
    if measured.get(key) is Some(values) {
      return values[index - start]
    }
    let wrapping = if square { Some((self, page_index, y)) } else { None }
    let values = kept_required(
      cache,
      probe,
      paragraphs[start:].to_owned(),
      following,
      page,
      profile,
      additive,
      wrapping,
    )
    if measured.length() < 32 {
      measured[key] = values
    }
    values[index - start]
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
    let required = required_at(
      self.page,
      self.pages.length() - 1,
      index,
      self.y + self.gap + spacing,
    )
    if self.y + self.gap + spacing + required > limit &&
      (
        self.pages.last().unwrap().lines.any(line => !line.caretOnly) ||
        !self.pages.last().unwrap().borders.is_empty()
      ) {
      let fits_next = try
        required_at(
          next,
          self.pages.length(),
          index,
          next.top + paragraph.before,
        ) <=
        full
      catch {
        @failure.Failure(code="layout-overflow" | "invalid-style", ..) => false
        error => raise error
      }
      if fits_next {
        self.next_page()
      }
    }
    let required = required_at(
      self.page,
      self.pages.length() - 1,
      index,
      self.y + self.gap + spacing,
    )
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
