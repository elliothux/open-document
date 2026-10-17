///|
priv struct Pagination {
  page : PageSetup
  pages : Array[PageFrame]
  mut y : Double
  mut count : Int
  mut after : Double
  mut gap : Double
}

///|
fn Pagination::new(page : PageSetup) -> Pagination {
  {
    page,
    pages: [
      {
        width: page.width,
        height: page.height,
        lines: [],
        borders: [],
        fills: [],
        cellAreas: [],
      },
    ],
    y: page.top,
    count: 0,
    after: 0,
    gap: 0,
  }
}

///|
fn Pagination::next_page(self : Pagination) -> Unit raise @failure.Failure {
  guard self.pages.length() < 1024 else {
    @failure.reject("limit-exceeded", "Page budget exceeded")
  }
  self.pages.push({
    width: self.page.width,
    height: self.page.height,
    lines: [],
    borders: [],
    fills: [],
    cellAreas: [],
  })
  self.y = self.page.top
  self.after = 0
  self.gap = 0
}

///|
fn Pagination::fit(
  self : Pagination,
  height : Double,
) -> Unit raise @failure.Failure {
  guard height > 0 &&
    height <= self.page.height - self.page.top - self.page.bottom else {
    @failure.reject(
      "layout-overflow", "Object is taller than the page content area",
    )
  }
  if self.y + height > self.page.height - self.page.bottom {
    self.next_page()
  }
}

///|
fn Pagination::place(
  self : Pagination,
  line : Line,
  left : Double,
  top : Double,
  images : Images,
) -> Unit raise @failure.Failure {
  self.count += 1
  guard self.count <= 32768 else {
    @failure.reject("limit-exceeded", "Line budget exceeded")
  }
  for image in line.images {
    ignore(images.get(image.key))
  }
  let x = left + line.x
  let y = top
  self.pages.last().unwrap().lines.push({
    ..line,
    x,
    y,
    areaX: left + line.areaX,
    bars: line.bars.map(position => left + position),
    marker: line.marker.map(run => {
      ..run.copy_geometry(),
      x: x + run.x,
      baseline: top + run.baseline,
    }),
    carets: line.carets.map(caret => {
      ..caret,
      before: x + caret.before,
      after: x + caret.after,
    }),
    runs: line.runs.map(run => {
      ..run.copy_geometry(),
      x: x + run.x,
      baseline: top + run.baseline,
    }),
    images: line.images.map(image => {
      ..image,
      x: x + image.x,
      y: top + image.y,
    }),
  })
}

///|
fn Paragraph::validate_spacing(
  self : Paragraph,
  page_height : Double,
) -> Unit raise @failure.Failure {
  guard self.nominalSize > 0 &&
    self.nominalSize <= 1024 &&
    self.before >= 0 &&
    self.after >= 0 &&
    self.before <= page_height &&
    self.after <= page_height else {
    @failure.reject("invalid-style", "Invalid paragraph spacing")
  }
}

///|
fn Pagination::paragraph(
  self : Pagination,
  cache : ParagraphCache,
  probe : TextProbe,
  paragraph : Paragraph,
  profile : Map[String, String],
  images : Images,
  additive : Bool,
) -> Unit raise @failure.Failure {
  if paragraph.pageBreakBefore &&
    (
      self.pages.last().unwrap().lines.iter().any(line => !line.caretOnly) ||
      !self.pages.last().unwrap().borders.is_empty()
    ) {
    self.next_page()
  }
  paragraph.validate_spacing(self.page.height)
  self.y += if additive {
    self.after + paragraph.before
  } else {
    self.after.max(paragraph.before)
  }
  self.y += self.gap
  self.after = 0
  self.gap = 0
  let measured_lines = cache.lines(
    probe,
    paragraph,
    profile,
    self.page.width - self.page.left - self.page.right,
  )
  if paragraph.keepLines && !measured_lines.any(line => line.line.y == -1) {
    let mut height = 0.0
    let mut first_line = true
    for measured in measured_lines {
      if measured.line.caretOnly {
        continue
      }
      height += measured.spaced(paragraph.line, first_line).height
      first_line = false
    }
    let limit = self.page.height - self.page.bottom
    if self.y + height > limit {
      if self.pages.last().unwrap().lines.any(line => !line.caretOnly) ||
        !self.pages.last().unwrap().borders.is_empty() {
        self.next_page()
      } else if height <= limit - self.page.top {
        self.y = self.page.top
      }
    }
  }
  let mut ended_with_break = false
  let mut first = true
  for measured in measured_lines {
    let mut line = measured.spaced(paragraph.line, first)
    if line.text.is_empty() && line.marker.is_empty() && line.y == -1 {
      self.place(line, self.page.left, self.y, images)
      if !ended_with_break {
        self.next_page()
      }
      ended_with_break = true
      first = true
      continue
    }
    if line.caretOnly {
      self.place(line, self.page.left, self.y, images)
      continue
    }
    if self.y + line.height > self.page.height - self.page.bottom {
      self.next_page()
      line = measured.spaced(paragraph.line, true)
    }
    self.fit(line.height)
    self.place(line, self.page.left, self.y, images)
    self.y += line.height
    self.gap = paragraph.line.gap(measured.textHeight)
    first = false
    ended_with_break = line.y == -1
    if line.y == -1 {
      self.next_page()
      first = true
    }
  }
  if !ended_with_break {
    self.after = paragraph.after
  }
}

///|
fn Table::left(
  table : Table,
  page : PageSetup,
) -> Double raise @failure.Failure {
  let width = table.widths
    .iter()
    .fold(init=0.0, (total, width) => total + width)
  let available = page.width - page.left - page.right
  guard width > 0 && width <= available else {
    @failure.reject("layout-overflow", "Table exceeds page width")
  }
  page.left +
  (match table.align {
    "center" => (available - width) / 2
    "right" => available - width
    _ => 0
  })
}

///|
pub fn paginate(
  probe : TextProbe,
  flow : Flow,
  profile : Map[String, String],
  images : Images,
) -> Layout raise @failure.Failure {
  probe.check()
  flow.page.validate()
  for index, table in flow.tables {
    guard table.beforeParagraph >= 0 &&
      table.beforeParagraph <= flow.paragraphs.length() &&
      (
        index == 0 ||
        flow.tables[index - 1].beforeParagraph <= table.beforeParagraph
      ) else {
      @failure.reject("invalid-table", "Table body position is invalid")
    }
  }
  guard flow.headerDistance >= 0 && flow.headerDistance <= flow.page.height else {
    @failure.reject("invalid-style", "Invalid header distance")
  }
  let cache = ParagraphCache::new(probe, profile)
  let mut top = flow.page.top
  for header in flow.headers {
    let mut height = flow.headerDistance
    let mut gap = 0.0
    let mut last_gap = 0.0
    for paragraph in header {
      paragraph.validate_spacing(flow.page.height)
      guard !paragraph.pageBreakBefore else {
        @failure.reject(
          "unsupported-layout", "Invalid empty header spacing or page break",
        )
      }
      height += paragraph.before + paragraph.after
      height += gap
      last_gap = paragraph.line.terminal_gap(paragraph.nominalSize)
      let mut first = true
      for
        measured in cache.lines(
          probe,
          paragraph,
          profile,
          flow.page.width - flow.page.left - flow.page.right,
        ) {
        let line = measured.spaced(paragraph.line, first)
        height += line.height
        gap = paragraph.line.gap(measured.textHeight)
        first = false
      }
    }
    top = top.max(height + last_gap)
  }
  let page = { ..flow.page, top, }
  page.validate()
  let pagination = Pagination::new(page)
  let (reflowed, reused, next) = pagination.body(
    probe, flow, cache, profile, images,
  )
  let result : Layout = {
    revision: flow.revision,
    shapedParagraphs: cache.shaped,
    reusedParagraphs: cache.reused,
    reflowedPages: reflowed,
    reusedPages: reused,
    profile: profile.copy(),
    pages: pagination.pages,
    diagnostics: flow.diagnostics.copy(),
    outlines: probe.outline_resources(),
    fonts: probe.font_info(),
  }
  probe.paragraphs = cache.current
  probe.pagination = next
  result
}
