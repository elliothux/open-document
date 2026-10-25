///|
pub(all) struct Column {
  width : Double
  gap : Double
} derive(ToJson)

///|
pub extend Column with ToJson::{to_json}

///|
pub(all) struct Columns {
  count : Int
  gap : Double
  separator : Bool
  custom : Array[Column]
} derive(ToJson)

///|
pub extend Columns with ToJson::{to_json}

///|
pub fn Columns::new(
  count~ : Int = 1,
  gap~ : Double = 36,
  separator~ : Bool = false,
  custom~ : Array[Column] = [],
) -> Columns {
  { count, gap, separator, custom, }
}

///|
fn Columns::frame(
  self : Columns,
  page : PageSetup,
  index : Int,
) -> (Double, Double) {
  let full = page.width - page.left - page.right
  if self.custom.is_empty() {
    let width = (full - self.gap * (self.count - 1).to_double()) /
      self.count.to_double()
    return (page.left + index.to_double() * (width + self.gap), width)
  }
  let left = self.custom[:index]
    .iter()
    .fold(init=page.left, (left, column) => left + column.width + column.gap)
  (
    left,
    if index == self.count - 1 {
      page.width - page.right - left
    } else {
      self.custom[index].width
    },
  )
}

///|
pub fn Columns::width(
  self : Columns,
  page : PageSetup,
) -> Double raise @failure.Failure {
  guard self.count >= 1 &&
    self.count <= 12 &&
    !self.gap.is_nan() &&
    !self.gap.is_inf() &&
    self.gap >= 0 &&
    self.gap <= 14400 &&
    (self.custom.is_empty() || self.custom.length() == self.count) &&
    self.custom.all(column => {
      !column.width.is_nan() &&
      !column.width.is_inf() &&
      column.width >= 12 &&
      column.width <= 14400 &&
      !column.gap.is_nan() &&
      !column.gap.is_inf() &&
      column.gap >= 0 &&
      column.gap <= 14400 &&
      column.width * 20 == (column.width * 20).round() &&
      column.gap * 20 == (column.gap * 20).round()
    }) else {
    @failure.reject("invalid-style", "Invalid page columns")
  }
  let width = Array::makei(self.count, index => self.frame(page, index).1).fold(
    init=14400.0,
    (width, candidate) => width.min(candidate),
  )
  guard width >= 12 else {
    @failure.reject(
      "layout-overflow", "Columns require at least 12pt of text width",
    )
  }
  width
}

///|
pub fn Columns::width_at(
  self : Columns,
  page : PageSetup,
  x : Double,
) -> Double raise @failure.Failure {
  ignore(self.width(page))
  guard !x.is_nan() && !x.is_inf() else {
    @failure.reject("invalid-position", "Invalid column coordinate")
  }
  for index in 0..<self.count {
    let (left, width) = self.frame(page, index)
    if x >= left &&
      (x < left + width || (index == self.count - 1 && x == left + width)) {
      return width
    }
  }
  @failure.reject("invalid-position", "Position is outside column content")
}

///|
fn Pagination::sheet_break(self : Pagination) -> Unit raise @failure.Failure {
  self.next_page()
  while self.pages.length() % self.columns.count != 1 % self.columns.count {
    self.next_page()
  }
}

///|
fn Pagination::finish_columns(self : Pagination) -> Unit {
  if self.columns.count == 1 {
    return
  }
  let frames = self.pages.copy()
  self.pages.clear()
  for index, frame in frames {
    if index % self.columns.count == 0 {
      self.pages.push(frame)
    } else {
      let page = self.pages.last().unwrap()
      page.lines.append(frame.lines)
      page.borders.append(frame.borders)
      page.fills.append(frame.fills)
      page.cellAreas.append(frame.cellAreas)
      if self.columns.separator &&
        (!frame.lines.is_empty() || !frame.cellAreas.is_empty()) {
        let setup = self.page_at(index)
        page.fills.push({
          x: setup.left -
          (if self.columns.custom.is_empty() {
            self.columns.gap
          } else {
            self.columns.custom[index % self.columns.count - 1].gap
          }) /
          2 -
          0.375,
          y: setup.top,
          width: 0.75,
          height: setup.height - setup.top - setup.bottom,
          color: "000000",
        })
      }
    }
  }
}

///|
fn column_body(
  probe : TextProbe,
  flow : Flow,
  cache : ParagraphCache,
  profile : Map[String, String],
  images : Images,
  setups : Array[PageSetup],
  page_setups : Array[PageSetup],
  pendingNotes~ : Array[(Line, Double)] = [],
  continuation~ : SectionContinuation? = None,
) -> (Pagination, Int, Int, PaginationCache?) raise @failure.Failure {
  let columns = flow.columns
  guard pendingNotes.is_empty() || columns.count == 1 else {
    @failure.reject(
      "unsupported-layout", "Footnote continuation in columns requires shared reservations",
    )
  }
  let note_references = note_references(probe, flow, cache, profile, images)
  ignore(columns.width(flow.page))
  for setup in setups + page_setups {
    ignore(columns.width(setup))
  }
  let run = fn(balance : (Int, Double)?) raise @failure.Failure {
    let wraps = continuation
      .map(state => !wrapping_rects([state.frame], 1).is_empty())
      .unwrap_or(false) ||
      flow.paragraphs.any(p => {
        p.spans.any(span => {
          span.drawing
          .bind(image => image.anchor)
          .map(anchor => anchor.wrapping != "none")
          .unwrap_or(false)
        })
      })
    let mut wrapping = if wraps {
      probe.pagination
      .map(old => wrapping_rects(old.pages, columns.count))
      .unwrap_or_else(() => {
        continuation
        .map(state => wrapping_rects([state.frame], 1))
        .unwrap_or([])
      })
    } else {
      []
    }
    for _ in 0..<8 {
      let pagination = Pagination::new(
        setups[0],
        setups~,
        pageSetups=page_setups,
        columns~,
        balance~,
        anchorPage=Some(flow.page),
        wrapping=wrapping.copy(),
        noteReferences=note_references,
        pendingNotes~,
        continuation~,
      )
      let (reflowed, reused, next) = pagination.body(
        probe,
        { ..flow, page: pagination.page, },
        cache,
        profile,
        images,
      )
      let current = wrapping_rects(pagination.pages, columns.count)
      if !wraps || Json(current) == Json(wrapping) {
        return (pagination, reflowed, reused, next)
      }
      wrapping = current
    }
    @failure.reject(
      "layout-overflow", "Floating image wrapping did not converge within eight passes",
    )
  }
  let initial = run(None)
  if columns.count == 1 {
    return initial
  }
  let last = (initial.0.pages.length() - 1) / columns.count
  let setup = initial.0.page_at(last * columns.count)
  let mut low = 1
  let mut high = ((setup.height - setup.top - setup.bottom) * 20)
    .ceil()
    .to_int()
  let mut best = initial
  for _ in 0..<20 {
    if low >= high {
      break
    }
    let middle = low + (high - low) / 2
    let trial = try run(Some((last, middle.to_double() / 20))) catch {
      @failure.Failure(code="layout-overflow", ..) => None
      error => raise error
    } noraise {
      value => Some(value)
    }
    if trial is Some(value) &&
      value.0.pages.length() <= (last + 1) * columns.count {
      best = value
      high = middle
    } else {
      low = middle + 1
    }
  }
  let (pagination, reflowed, reused, next) = best
  pagination.finish_columns()
  let reused = if reflowed == 0 {
    pagination.pages.length()
  } else {
    reused / columns.count
  }
  (pagination, pagination.pages.length() - reused, reused, next)
}
