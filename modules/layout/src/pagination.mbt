///|
priv struct Pagination {
  page : PageSetup
  pages : Array[PageFrame]
  mut y : Double
  mut count : Int
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
      },
    ],
    y: page.top,
    count: 0,
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
  })
  self.y = self.page.top
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
    runs: line.runs.map(run => {
      ..run,
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
  guard self.before >= 0 &&
    self.after >= 0 &&
    self.before <= page_height &&
    self.after <= page_height else {
    @failure.reject("invalid-style", "Invalid paragraph spacing")
  }
}

///|
fn Pagination::paragraph(
  self : Pagination,
  probe : TextProbe,
  paragraph : Paragraph,
  profile : Map[String, String],
  images : Images,
) -> Unit raise @failure.Failure {
  if paragraph.pageBreakBefore &&
    (
      !self.pages.last().unwrap().lines.is_empty() ||
      !self.pages.last().unwrap().borders.is_empty()
    ) {
    self.next_page()
  }
  paragraph.validate_spacing(self.page.height)
  self.y += paragraph.before
  let mut ended_with_break = false
  for
    line in paragraph_lines(
      probe,
      paragraph,
      profile,
      self.page.width - self.page.left - self.page.right,
    ) {
    if line.text.is_empty() && line.y == -1 {
      self.next_page()
      ended_with_break = true
      continue
    }
    self.fit(line.height)
    self.place(line, self.page.left, self.y, images)
    self.y += line.height
    ended_with_break = line.y == -1
    if line.y == -1 {
      self.next_page()
    }
  }
  if !ended_with_break {
    self.y += paragraph.after
  }
}

///|
fn Pagination::table(
  self : Pagination,
  probe : TextProbe,
  table : Table,
  profile : Map[String, String],
  images : Images,
) -> Unit raise @failure.Failure {
  let width = table.widths
    .iter()
    .fold(init=0.0, (total, width) => total + width)
  let available = self.page.width - self.page.left - self.page.right
  guard table.padding >= 0 && table.verticalPadding >= 0 else {
    @failure.reject("invalid-style", "Negative table cell margins")
  }
  guard width > 0 && width <= available else {
    @failure.reject("layout-overflow", "Table exceeds page width")
  }
  let left = self.page.left +
    (match table.align {
      "center" => (available - width) / 2
      "right" => available - width
      _ => 0
    })
  for row_index, row in table.rows {
    guard row.length() == table.widths.length() else {
      @failure.reject("invalid-table", "Table grid differs from row")
    }
    let cells : Array[Array[(Line, Double)]] = []
    let border = if table.borders { 0.5 } else { 0 }
    let mut height = (table.heights[row_index] + border).max(
      table.verticalPadding * 2 + border,
    )
    for column, paragraphs in row {
      let lines : Array[(Line, Double)] = []
      let mut y = table.verticalPadding + border
      for paragraph in paragraphs {
        paragraph.validate_spacing(self.page.height)
        guard !paragraph.pageBreakBefore else {
          @failure.reject(
            "unsupported-layout", "Page breaks inside table rows are unsupported",
          )
        }
        y += paragraph.before
        for
          line in paragraph_lines(
            probe,
            paragraph,
            profile,
            table.widths[column] - table.padding * 2,
          ) {
          guard line.y != -1 else {
            @failure.reject(
              "unsupported-layout", "Page breaks inside table rows are unsupported",
            )
          }
          lines.push((line, y))
          y += line.height
        }
        y += paragraph.after
      }
      height = height.max(y + table.verticalPadding + border)
      cells.push(lines)
    }
    self.fit(height)
    let mut x = left
    for column, cell in cells {
      let color = table.fills[row_index][column]
      if !color.is_empty() {
        self.pages.last().unwrap().fills.push({
          x,
          y: self.y,
          width: table.widths[column],
          height,
          color,
        })
      }
      for (line, offset) in cell {
        self.place(line, x + table.padding, self.y + offset, images)
      }
      if table.borders {
        self.pages.last().unwrap().borders.push({
          x,
          y: self.y,
          width: table.widths[column],
          height,
        })
      }
      x += table.widths[column]
    }
    self.y += height
  }
  if table.borders {
    self.y += 0.5
  }
}

///|
pub fn paginate(
  probe : TextProbe,
  flow : Flow,
  profile : Map[String, String],
  images : Images,
) -> Layout raise @failure.Failure {
  flow.page.validate()
  guard flow.headerDistance >= 0 && flow.headerDistance <= flow.page.height else {
    @failure.reject("invalid-style", "Invalid header distance")
  }
  let mut top = flow.page.top
  for header in flow.headers {
    let mut height = flow.headerDistance
    for paragraph in header {
      paragraph.validate_spacing(flow.page.height)
      guard !paragraph.pageBreakBefore else {
        @failure.reject(
          "unsupported-layout", "Invalid empty header spacing or page break",
        )
      }
      height += paragraph.before + paragraph.after
      for
        line in paragraph_lines(
          probe,
          paragraph,
          profile,
          flow.page.width - flow.page.left - flow.page.right,
        ) {
        height += line.height
      }
    }
    top = top.max(height)
  }
  let page = { ..flow.page, top, }
  page.validate()
  let pagination = Pagination::new(page)
  let mut paragraph = 0
  let mut table = 0
  while paragraph < flow.paragraphs.length() || table < flow.tables.length() {
    if paragraph < flow.paragraphs.length() &&
      (
        table == flow.tables.length() ||
        flow.paragraphs[paragraph].id < flow.tables[table].id
      ) {
      pagination.paragraph(probe, flow.paragraphs[paragraph], profile, images)
      paragraph += 1
    } else {
      pagination.table(probe, flow.tables[table], profile, images)
      table += 1
    }
  }
  {
    revision: flow.revision,
    profile: profile.copy(),
    pages: pagination.pages,
    diagnostics: flow.diagnostics.copy(),
    outlines: probe.outline_resources(),
    fonts: probe.font_info(),
  }
}
