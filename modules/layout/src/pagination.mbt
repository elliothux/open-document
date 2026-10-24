///|
priv struct Pagination {
  columns : Columns
  balance : (Int, Double)?
  mut page : PageSetup
  anchorPage : PageSetup
  setups : Array[PageSetup]
  pageSetups : Array[PageSetup]
  pages : Array[PageFrame]
  tables : Map[Int, Table]
  mut active_table : Int?
  mut y : Double
  mut count : Int
  mut after : Double
  mut gap : Double
  wrapping : Array[WrappingRect]
  placedWrapping : Map[(Int, Int), Unit]
  noteReferences : Map[(Int, Int), Array[(Line, Double)]]
  noteUsed : Set[(Int, Int)]
  notePending : Array[(Line, Double)]
  mut noteCursor : Int
  mut noteBodyHeight : Double
  notePages : Map[Int, Array[Line]]
  noteHeights : Map[Int, Double]
  noteContinuations : Set[Int]
}

///|
fn Pagination::new(
  page : PageSetup,
  setups~ : Array[PageSetup] = [],
  pageSetups~ : Array[PageSetup] = [],
  columns~ : Columns = Columns::new(),
  balance~ : (Int, Double)? = None,
  anchorPage~ : PageSetup? = None,
  wrapping~ : Array[WrappingRect] = [],
  noteReferences~ : Map[(Int, Int), Array[(Line, Double)]] = Map([]),
  pendingNotes~ : Array[(Line, Double)] = [],
) -> Pagination {
  let anchor_page = anchorPage.unwrap_or(page)
  let page = pageSetups.get(0).unwrap_or(page)
  let result : Pagination = {
    columns,
    balance,
    page,
    anchorPage: anchor_page,
    setups,
    pageSetups,
    tables: Map([]),
    active_table: None,
    pages: [
      {
        width: page.width,
        height: page.height,
        lines: [],
        borders: [],
        fills: [],
        cellAreas: [],
        pageBorders: [],
      },
    ],
    y: page.top,
    count: 0,
    after: 0,
    gap: 0,
    wrapping,
    placedWrapping: Map([]),
    noteReferences,
    noteUsed: Set([]),
    notePending: pendingNotes.copy(),
    noteCursor: 0,
    noteBodyHeight: 0,
    notePages: Map([]),
    noteHeights: Map([]),
    noteContinuations: Set([]),
  }
  result.page = result.page_at(0)
  result.y = result.page.top
  if !pendingNotes.is_empty() {
    result.noteContinuations.add(0)
  }
  result
}

///|
fn Pagination::next_page(self : Pagination) -> Unit raise @failure.Failure {
  guard self.pages.length() < 1024 * self.columns.count else {
    @failure.reject("limit-exceeded", "Page budget exceeded")
  }
  self.page = self.page_at(self.pages.length())
  self.pages.push({
    width: self.page.width,
    height: self.page.height,
    lines: [],
    borders: [],
    fills: [],
    cellAreas: [],
    pageBorders: [],
  })
  self.y = self.page.top
  self.after = 0
  self.gap = 0
  if self.noteCursor < self.notePending.length() {
    self.noteContinuations.add(self.pages.length() - 1)
  }
  self.reserve_pending_notes(self.noteBodyHeight)
}

///|
fn Pagination::fit(
  self : Pagination,
  height : Double,
  square~ : Bool = true,
) -> Unit raise @failure.Failure {
  guard height > 0 else {
    @failure.reject(
      "layout-overflow", "Object is taller than the page content area",
    )
  }
  for
    _ in 0..<(3 +
    self.wrapping.length() +
    self.notePending.length() -
    self.noteCursor) {
    self.avoid_wrapping(height, square~)
    if self.y + height <= self.page.height - self.page.bottom {
      return
    }
    self.next_page()
  }
  @failure.reject(
    "layout-overflow", "Object is taller than the page content area",
  )
}

///|
fn Pagination::page_at(self : Pagination, index : Int) -> PageSetup {
  let physical = index / self.columns.count
  let page = self.sheet_setup(physical)
  if self.columns.count == 1 {
    return page
  }
  let (left, width) = self.columns.frame(page, index % self.columns.count)
  {
    ..page,
    left,
    right: page.width - left - width,
    bottom: if self.balance is Some((target, height)) && target == physical {
      page.height - page.top - height
    } else {
      page.bottom
    },
  }
}

///|
fn Pagination::sheet_setup(self : Pagination, physical : Int) -> PageSetup {
  if self.pageSetups.get(physical) is Some(page) {
    page
  } else if self.setups.is_empty() {
    self.page
  } else {
    self.setups[if physical == 0 {
      0
    } else if physical % 2 == 1 {
      1
    } else {
      2
    }]
  }
}

///|
fn Pagination::place(
  self : Pagination,
  line : Line,
  left : Double,
  top : Double,
  images : Images,
  page? : Int,
) -> Unit raise @failure.Failure {
  self.count += 1
  guard self.count <= 32768 else {
    @failure.reject("limit-exceeded", "Line budget exceeded")
  }
  for image in line.drawings {
    if image.content is Picture(key, _) {
      ignore(images.get(key))
    }
  }
  let x = left + line.x
  let y = top
  let target = page.unwrap_or(self.pages.length() - 1)
  let placed = self.pages[target]
  let paragraph_top = placed.lines
    .iter()
    .find_first(prior => prior.paragraph == line.paragraph)
    .map(prior => prior.y)
    .unwrap_or(top)
  let physical = self.anchorPage
  let frame = self.page_at(target)
  placed.lines.push({
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
    drawings: line.drawings.map(image => {
      if image.anchor is Some(anchor) {
        {
          ..image,
          x: anchor.horizontal.position(
            (0, frame.width),
            (physical.left, physical.width - physical.left - physical.right),
            (frame.left, frame.width - frame.left - frame.right),
            image.width,
          ),
          y: anchor.vertical.position(
            (0, frame.height),
            (physical.top, physical.height - physical.top - physical.bottom),
            (paragraph_top, 0),
            image.height,
          ),
        }
      } else {
        { ..image, x: x + image.x, y: top + image.y, }
      }
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
  startOffset~ : Int = 0,
) -> Unit raise @failure.Failure {
  if startOffset == 0 &&
    paragraph.pageBreakBefore &&
    (
      self.pages.last().unwrap().lines.iter().any(line => !line.caretOnly) ||
      !self.pages.last().unwrap().borders.is_empty()
    ) {
    self.sheet_break()
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
  let available = fn() { self.page.width - self.page.left - self.page.right }
  let mut start_offset = startOffset
  let mut finished = false
  let mut ended_with_break = false
  let mut ended_with_page_break = false
  let mut first = true
  while !finished {
    let width = available()
    let initial_lines = cache.lines(
      probe,
      paragraph,
      profile,
      width,
      startOffset=start_offset,
    )
    if initial_lines.get(0) is Some(measured) {
      self.noteBodyHeight = measured.spaced(paragraph.line, true).height
      self.reserve_pending_notes(self.noteBodyHeight)
    }
    if initial_lines.get(0) is Some(measured) &&
      self.y + measured.spaced(paragraph.line, first).height <=
      self.page.height - self.page.bottom {
      ignore(self.detach_wrapping_images(measured.line, images))
    }
    let origin = (self.pages.length() - 1, self.y)
    let plan = if self.wrapping.any(rect => rect.wrapping == "square") ||
      paragraph.spans.any(span => {
        span.drawing
        .bind(image => image.anchor)
        .map(anchor => anchor.wrapping == "square")
        .unwrap_or(false)
      }) {
      Some(self.square_lines(probe, paragraph, profile, start_offset, first))
    } else {
      None
    }
    let measured_lines = plan.map(plan => plan.lines).unwrap_or(initial_lines)
    if start_offset == 0 &&
      paragraph.keepLines &&
      !measured_lines.any(line => line.line.y < 0) {
      let mut height = 0.0
      let mut first_line = true
      for measured in measured_lines {
        if measured.line.caretOnly {
          continue
        }
        let current = measured.spaced(paragraph.line, first_line).height
        height = self.wrapping_floor(
            self.pages.length() - 1,
            self.y + height,
            current,
            square=plan is None,
          ) -
          self.y +
          current
        first_line = false
      }
      let limit = self.page.height - self.page.bottom
      if self.y + height > limit {
        if self.pages.last().unwrap().lines.any(line => !line.caretOnly) ||
          !self.pages.last().unwrap().borders.is_empty() ||
          self.pages.last().unwrap().lines.any(line => {
            line.paragraph == paragraph.id &&
            line.drawings.any(image => {
              image.anchor is Some(anchor) && anchor.wrapping != "none"
            })
          }) {
          self.next_page()
        } else if height <= limit - self.page.top {
          self.y = self.page.top
        }
      }
    }
    if available() != width ||
      (plan is Some(_) && origin != (self.pages.length() - 1, self.y)) {
      continue
    }
    let breaks = self.widow_breaks(
      paragraph, measured_lines, cache, probe, profile,
    )
    if available() != width ||
      (plan is Some(_) && origin != (self.pages.length() - 1, self.y)) {
      continue
    }
    finished = true
    for index, measured in measured_lines {
      if breaks.contains(index) {
        self.next_page()
        first = true
      }
      if plan is Some(plan) {
        let (page, y, planned_first) = plan.positions[index]
        while self.pages.length() - 1 < page {
          self.next_page()
          first = true
        }
        if self.pages.length() - 1 != page ||
          self.y > y + 0.0000001 ||
          first != planned_first {
          start_offset = measured.line.start
          finished = false
          break
        }
        self.y = y
      }
      if available() != width {
        start_offset = measured.line.start
        finished = false
        break
      }
      let mut line = measured.spaced(paragraph.line, first)
      if line.text.is_empty() && line.marker.is_empty() && line.y < 0 {
        self.place(line, self.page.left, self.y, images)
        if line.y == -2 {
          self.next_page()
        } else if !ended_with_page_break {
          self.sheet_break()
        }
        ended_with_break = true
        ended_with_page_break = line.y == -1
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
        first = true
        if available() != width {
          start_offset = line.start
          finished = false
          break
        }
      }
      let new_anchor = plan is Some(_) &&
        line.drawings.any(image => {
          image.anchor is Some(anchor) &&
          anchor.wrapping != "none" &&
          !self.placedWrapping.contains((line.paragraph, image.start))
        })
      line = self.detach_wrapping_images(line, images)
      if new_anchor {
        start_offset = line.start
        finished = false
        break
      }
      let previous_page = self.pages.length()
      self.fit_note_references(
        [line],
        line.height.max(measured.spaced(paragraph.line, true).height),
        square=plan is None,
      )
      if self.pages.length() != previous_page {
        line = measured.spaced(paragraph.line, true)
        first = true
      }
      self.fit(line.height, square=plan is None)
      if available() != width {
        start_offset = line.start
        finished = false
        first = true
        break
      }
      self.place(line, self.page.left, self.y, images)
      self.y += line.height
      self.gap = paragraph.line.gap(measured.textHeight)
      first = false
      ended_with_break = line.y < 0
      ended_with_page_break = line.y == -1
      if line.y < 0 {
        if line.y == -2 {
          self.next_page()
        } else {
          self.sheet_break()
        }
        first = true
      }
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
  flow.pageBorders.validate()
  flow.validate_sections()
  flow.validate_floating_images()
  guard flow.background.length() == 6 &&
    flow.background.iter().all(c => c.is_ascii_hexdigit()) else {
    @failure.reject("invalid-style", "Invalid page background color")
  }
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
  flow.validate_notes()
  let cache = ParagraphCache::new(probe, profile)
  if !flow.sectionBreaks.is_empty() {
    let old = probe.pagination
    // shortcut: Retain paragraph shaping until page-cache positions include section boundaries.
    probe.pagination = None
    errdefer {
      probe.pagination = old
    }
    let (pages, running, diagnostics) = paginate_sections(
      probe, flow, cache, profile, images,
    )
    probe.paragraphs = cache.current
    return {
      background: flow.background,
      revision: flow.revision,
      shapedParagraphs: cache.shaped,
      reusedParagraphs: cache.reused,
      reflowedPages: pages.length(),
      reusedPages: 0,
      profile: profile.copy(),
      pages,
      running,
      diagnostics: flow.diagnostics + diagnostics,
      outlines: probe.outline_resources(),
      fonts: probe.font_info(),
    }
  }
  let (pagination, running, reflowed, reused, next, diagnostics) = paginate_running(
    probe, flow, cache, profile, images,
  )
  guard running.iter().fold(init=0, (total, lines) => total + lines.length()) <=
    32768 - pagination.count else {
    @failure.reject(
      "limit-exceeded", "Repeated header and footer line budget exceeded",
    )
  }
  let result : Layout = {
    background: flow.background,
    revision: flow.revision,
    shapedParagraphs: cache.shaped,
    reusedParagraphs: cache.reused,
    reflowedPages: reflowed,
    reusedPages: reused,
    profile: profile.copy(),
    running,
    pages: pagination.pages.mapi((index, page) => {
      ..page,
      pageBorders: if flow.pageBorders.zOrder == "front" {
        flow.pageBorders.fills(flow.page, index)
      } else {
        []
      },
      fills: if flow.pageBorders.zOrder == "back" {
        [..flow.pageBorders.fills(flow.page, index), ..page.fills]
      } else {
        page.fills
      },
    }),
    diagnostics: flow.diagnostics + diagnostics,
    outlines: probe.outline_resources(),
    fonts: probe.font_info(),
  }
  probe.paragraphs = cache.current
  probe.pagination = next
  result
}
