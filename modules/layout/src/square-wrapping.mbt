///|
priv struct SquarePlan {
  lines : Array[MeasuredLine]
  positions : Array[(Int, Double, Bool)]
}

///|
fn Pagination::square_regions(
  self : Pagination,
  page : Int,
  y : Double,
  height : Double,
) -> Array[(Double, Double)] {
  let frame = self.page_at(page)
  let left = frame.left
  let right = frame.width - frame.right
  let mut regions = [(left, right)]
  for rect in self.wrapping {
    if rect.wrapping != "square" ||
      rect.page != page / self.columns.count ||
      y + height <= rect.top + 0.0000001 ||
      y >= rect.bottom - 0.0000001 {
      continue
    }
    let excluded = match rect.side {
      "left" =>
        if rect.left > left {
          (rect.left, right)
        } else {
          (right, right)
        }
      "right" =>
        if rect.right < right {
          (left, rect.right)
        } else {
          (left, left)
        }
      "largest" =>
        if right - rect.right > 0 && right - rect.right > rect.left - left {
          (left, rect.right)
        } else if rect.left - left > 0 && rect.left - left > right - rect.right {
          (rect.left, right)
        } else {
          (left, left)
        }
      _ => (rect.left, rect.right)
    }
    let mut a = excluded.0
    let mut b = excluded.1
    if b <= a || b <= left || a >= right {
      continue
    }
    // ONLYOFFICE absorbs square-wrap edge gaps smaller than 6.35 mm (18 pt).
    if a < left + 18 {
      a = left
    }
    if b > right - 18 {
      b = right
    }
    let next = []
    for (start, end) in regions {
      if b <= start || a >= end {
        next.push((start, end))
      } else {
        if a > start {
          next.push((start, a.min(end)))
        }
        if b < end {
          next.push((b.max(start), end))
        }
      }
    }
    regions = next
  }
  regions.map(region => (region.0 - left, region.1 - left))
}

///|
fn merged_fragments(
  fragments : Array[MeasuredLine],
  available : Double,
) -> MeasuredLine {
  let first = fragments[0]
  let last = fragments.last().unwrap()
  let baseline = fragments.fold(init=0.0, (value, item) => {
    value.max(item.baseline)
  })
  let descent = fragments.fold(init=0.0, (value, item) => {
    value.max(item.line.height - item.baseline)
  })
  let ascent = fragments.fold(init=0.0, (value, item) => {
    value.max(item.textAscent)
  })
  let text_descent = fragments.fold(init=0.0, (value, item) => {
    value.max(item.textHeight - item.textAscent)
  })
  let runs = []
  let images = []
  let marker = []
  let carets : Array[Caret] = []
  let bars = []
  for item in fragments {
    let line = item.line
    let dy = baseline - item.baseline
    runs.append(
      line.runs.map(run => {
        ..run,
        x: run.x + line.x,
        baseline: run.baseline + dy,
      }),
    )
    marker.append(
      line.marker.map(run => {
        ..run,
        x: run.x + line.x,
        baseline: run.baseline + dy,
      }),
    )
    images.append(
      line.images.map(image => {
        ..image,
        x: image.x + line.x,
        y: image.y + dy,
      }),
    )
    for caret in line.carets {
      let caret = {
        ..caret,
        before: caret.before + line.x,
        after: caret.after + line.x,
      }
      if carets.last() is Some(prior) && prior.offset == caret.offset {
        carets[carets.length() - 1] = { ..prior, after: caret.after, }
      } else {
        carets.push(caret)
      }
    }
    for bar in line.bars {
      if !bars.contains(bar) {
        bars.push(bar)
      }
    }
  }
  {
    textHeight: ascent + text_descent,
    textAscent: ascent,
    baseline,
    line: {
      ..first.line,
      text: fragments.map(item => item.line.text).join(""),
      end: last.line.end,
      x: 0,
      y: last.line.y,
      width: available,
      areaX: 0,
      areaWidth: available,
      height: baseline + descent,
      caretOnly: fragments.all(item => item.line.caretOnly),
      justified: fragments.any(item => item.line.justified),
      runs,
      marker,
      images,
      carets,
      bars,
    },
  }
}

///|
fn Pagination::square_row(
  self : Pagination,
  source : ParagraphSource,
  paragraph : Paragraph,
  page : Int,
  y : Double,
  start : Int,
  first : Bool,
) -> (MeasuredLine?, Double) raise @failure.Failure {
  let frame = self.page_at(page)
  let width = frame.width - frame.left - frame.right
  let mut height = (source.line)(start, 0, width).spaced(paragraph.line, first).height
  for _ in 0..<8 {
    let regions = self.square_regions(page, y, height)
    let fragments = []
    let mut offset = start
    for index in 0..<regions.length() {
      let (left, right) = regions[if paragraph.rtl {
          regions.length() - 1 - index
        } else {
          index
        }]
      let item = Some((source.line)(offset, left, right)) catch {
        @failure.Failure(code="layout-overflow", ..) => None
        error => raise error
      }
      guard item is Some(item) else { continue }
      fragments.push(item)
      offset = item.line.end
      if offset == source.text.length() ||
        item.line.y < 0 ||
        (offset > 0 && source.text[offset - 1] == 10) {
        break
      }
    }
    if fragments.is_empty() {
      return (None, height)
    }
    let merged = merged_fragments(fragments, width)
    let actual = merged.spaced(paragraph.line, first).height
    if actual <= height + 0.0000001 {
      return (Some(merged), actual)
    }
    height = actual
  }
  @failure.reject(
    "layout-overflow", "Square wrapping line metrics did not converge",
  )
}

///|
fn Pagination::square_lines(
  self : Pagination,
  probe : TextProbe,
  paragraph : Paragraph,
  profile : Map[String, String],
  start : Int,
  first : Bool,
  startPage? : Int,
  startY? : Double,
) -> SquarePlan raise @failure.Failure {
  let lines = []
  let positions = []
  let mut page = startPage.unwrap_or(self.pages.length() - 1)
  let mut y = startY.unwrap_or(self.y)
  let mut offset = start
  let mut first = first
  let frame = self.page_at(page)
  let mut width = frame.width - frame.left - frame.right
  let mut source = prepare_paragraph(
    probe,
    paragraph,
    profile,
    width,
    startOffset=start,
  )
  while offset < source.text.length() ||
        lines.is_empty() ||
        source.text.has_suffix("\n") ||
        source.text.has_suffix("\u000b") ||
        source.text.has_suffix("\u000c") {
    guard page < 1024 * self.columns.count && lines.length() < 32768 else {
      @failure.reject(
        "limit-exceeded", "Square wrapping page or line budget exceeded",
      )
    }
    let frame = self.page_at(page)
    let available = frame.width - frame.left - frame.right
    if width != available {
      width = available
      source = prepare_paragraph(
        probe,
        paragraph,
        profile,
        width,
        startOffset=offset,
      )
    }
    let (item, height) = self.square_row(
      source, paragraph, page, y, offset, first,
    )
    let floor = self.wrapping_floor(page, y, height, square=false)
    if y + height > frame.height - frame.bottom ||
      floor + height > frame.height - frame.bottom {
      guard height <= frame.height - frame.top - frame.bottom else {
        @failure.reject(
          "layout-overflow", "Object is taller than the page content area",
        )
      }
      page += 1
      y = self.page_at(page).top
      first = true
      continue
    }
    if floor > y {
      y = floor
      continue
    }
    guard item is Some(item) else {
      let bottom = self.wrapping
        .filter(rect => {
          rect.page == page / self.columns.count &&
          rect.wrapping == "square" &&
          rect.bottom > y &&
          rect.top < y + height &&
          rect.right > frame.left &&
          rect.left < frame.width - frame.right
        })
        .fold(init=frame.height, (value, rect) => value.min(rect.bottom))
      guard bottom > y else {
        @failure.reject("layout-overflow", "Square wrapping made no progress")
      }
      y = bottom
      continue
    }
    lines.push(item)
    positions.push((page, y, first))
    let line = item.spaced(paragraph.line, first)
    if offset == line.end {
      break
    }
    offset = line.end
    if !line.caretOnly {
      y += line.height
      first = false
    }
    if line.y < 0 {
      page += 1
      if line.y == -1 {
        while page % self.columns.count != 0 {
          page += 1
        }
      }
      y = self.page_at(page).top
      first = true
    }
    if offset == source.text.length() &&
      !(source.text.has_suffix("\n") ||
      source.text.has_suffix("\u000b") ||
      source.text.has_suffix("\u000c")) {
      break
    }
  }
  validate_paragraph_leaders(lines)
  { lines, positions, }
}
