///|
priv struct TimelinePeriod {
  first : Double
  next : Double
  label : String
}

///|
fn timeline_period_key(value : Double, level : Int) -> Int {
  let (year, month, _) = pivot_calendar_parts(value, false)
  match level {
    0 => year
    1 => year * 4 + (month - 1) / 3
    2 => year * 12 + month - 1
    _ => value.floor().to_int()
  }
}

///|
fn timeline_period(key : Int, level : Int) -> TimelinePeriod {
  if level == 3 {
    let (year, month, day) = pivot_calendar_parts(key.to_double(), false)
    return {
      first: key.to_double(),
      next: key.to_double() + 1,
      label: padded(year, 4) + "-" + padded(month, 2) + "-" + padded(day, 2),
    }
  }
  let (year, month, months) = match level {
    0 => (key, 1, 12)
    1 => (key / 4, key % 4 * 3 + 1, 3)
    _ => (key / 12, key % 12 + 1, 1)
  }
  let (next_year, next_month) = (
    year + (month + months - 1) / 12,
    (month + months - 1) % 12 + 1,
  )
  let epoch = pivot_date_epoch(false)
  {
    first: (calendar_ordinal(year, month, 1) - epoch).to_double(),
    next: (calendar_ordinal(next_year, next_month, 1) - epoch).to_double(),
    label: match level {
      0 => padded(year, 4)
      1 => padded(year, 4) + " Q" + (key % 4 + 1).to_string()
      _ => padded(year, 4) + "-" + padded(month, 2)
    },
  }
}

///|
fn SheetTimeline::label(self : SheetTimeline) -> String {
  let range = self.cache.state.selection.unwrap_or(self.cache.state.bounds)
  self.caption + ": " + range.start + " – " + range.end
}

///|
fn TimelineDrawing::paint_text(
  self : TimelineDrawing,
  primitives : Array[@layout.PositionedPrimitive],
  text : String,
  rect : @layout.Border,
  bold : Bool,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Unit raise @failure.Failure {
  if rect.width <= 0 || rect.height <= 0 || text.is_empty() {
    return
  }
  let block = probe.text_block(
    text,
    @layout.TextStyle::new(
      self.font + (if bold { "|bold" } else { "" }),
      self.size,
      self.text,
    ),
    profile,
    rect.width,
    false,
  )
  primitives.push(Clip(rect))
  primitives.push(
    Transform({
      a: 1,
      b: 0,
      c: 0,
      d: 1,
      e: rect.x,
      f: rect.y + (rect.height - block.height).max(0) / 2,
    }),
  )
  for line in block.lines {
    primitives.append(line)
  }
  primitives.push(Restore)
  primitives.push(Restore)
}

///|
fn TimelineDrawing::header_height(self : TimelineDrawing) -> Double {
  if self.control.header || self.control.time_level {
    (self.size * 1.8).max(18)
  } else {
    0
  }
}

///|
priv struct TimelineGeometry {
  lower : Int
  upper : Int
  first : Int
  header : Double
  line : Double
  width : Double
  column : Double
  selection : (Double, Double)?
  cells : Array[(Int, TimelinePeriod, @layout.Border)]
  handles : Array[(Int, Int, String, @layout.Border)]
}

///|
fn TimelineDrawing::geometry(
  self : TimelineDrawing,
  width : Double,
  height : Double,
) -> TimelineGeometry raise @failure.Failure {
  let view = self.control
  let bounds = view.cache.state.bounds
  let minimum = pivot_date_parse(bounds.start, false)
  let maximum = pivot_date_parse(bounds.end, false)
  let scroll = view.scroll
    .map(text => pivot_date_parse(text, false))
    .unwrap_or(minimum)
    .max(minimum)
    .min(maximum)
  let lower = timeline_period_key(minimum, view.level)
  let upper = timeline_period_key(maximum, view.level)
  let first = timeline_period_key(scroll, view.level)
  let selection = match view.cache.state.selection {
    None if view.cache.state.filterType == "unknown" =>
      Some(
        (
          timeline_period(lower, view.level).first,
          timeline_period(upper, view.level).next,
        ),
      )
    Some(range) =>
      Some(
        (
          pivot_date_parse(range.start, false),
          pivot_date_parse(range.end, false),
        ),
      )
    None => None
  }
  let header = self.header_height()
  let line = if view.selection_label { (self.size * 1.6).max(16) } else { 0.0 }
  let width = (width - 14.4).max(0)
  let column = (self.size * (if view.level == 3 { 7.0 } else { 5.0 })).max(36)
  let count = (width / column)
    .ceil()
    .to_int()
    .min(512)
    .min(upper - first + 1)
    .max(0)
  let label_y = 7.2 + header + line
  let bar_y = label_y + self.size * 1.5 + 3.6
  let bar_height = (height - bar_y - (if view.scrollbar { 18.0 } else { 7.2 }))
    .max(0)
    .min(20)
  let cells : Array[(Int, TimelinePeriod, @layout.Border)] = []
  for offset in 0..<count {
    let key = first + offset
    let x = 7.2 + offset.to_double() * column
    cells.push(
      (
        key,
        timeline_period(key, view.level),
        {
          x,
          y: bar_y,
          width: (width + 7.2 - x).min(column).max(0),
          height: bar_height,
        },
      ),
    )
  }
  let handles : Array[(Int, Int, String, @layout.Border)] = []
  if view.selected_range() is Some(range) {
    for (handle, value) in [(1, range.start), (2, range.end)] {
      let date = pivot_date_parse(value, false)
      let index = timeline_period_key(date, view.level)
      if cells.iter().find_first(cell => cell.0 == index)
        is Some((_, period, rect)) &&
        rect.height > 0 {
        let x = rect.x +
          column * (date - period.first) / (period.next - period.first)
        if x >= rect.x && x <= rect.x + rect.width {
          handles.push(
            (
              handle,
              index,
              value,
              {
                x: x - 3.6,
                y: rect.y - 3.6,
                width: 7.2,
                height: rect.height + 7.2,
              },
            ),
          )
        }
      }
    }
  }
  {
    lower,
    upper,
    first,
    header,
    line,
    width,
    column,
    selection,
    cells,
    handles,
  }
}

///|
// shortcut: Light1 uses workbook text/accent colors; match native differentials before claiming preset fidelity.
fn TimelineDrawing::paint(
  self : TimelineDrawing,
  primitives : Array[@layout.PositionedPrimitive],
  rect : @layout.Border,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Unit raise @failure.Failure {
  let view = self.control
  let bounds = view.cache.state.bounds
  let geometry = self.geometry(rect.width, rect.height)
  let { lower, upper, first, header, line, width, column, selection, cells, .. } = geometry
  let label_y = 7.2 + header + line
  let count = cells.length()
  primitives.push(Clip(rect))
  primitives.push(Transform({ a: 1, b: 0, c: 0, d: 1, e: rect.x, f: rect.y, }))
  primitives.push(
    Rectangle({
      x: 0,
      y: 0,
      width: rect.width,
      height: rect.height,
      color: "ffffff",
    }),
  )
  primitives.push(
    Stroke(
      {
        x: 0.375,
        y: 0.375,
        width: (rect.width - 0.75).max(0),
        height: (rect.height - 0.75).max(0),
      },
      self.accent,
      0.75,
    ),
  )
  if view.header {
    self.paint_text(
      primitives,
      view.caption,
      {
        x: 7.2,
        y: 7.2,
        width: (width - (if view.time_level { 60.0 } else { 0.0 })).max(0),
        height: header,
      },
      true,
      probe,
      profile,
    )
  }
  if view.time_level {
    self.paint_text(
      primitives,
      ["Years", "Quarters", "Months", "Days"][view.level],
      {
        x: (rect.width - 67.2).max(7.2),
        y: 7.2,
        width: width.min(60),
        height: header,
      },
      false,
      probe,
      profile,
    )
  }
  if view.selection_label {
    let range = view.cache.state.selection.unwrap_or(bounds)
    self.paint_text(
      primitives,
      range.start[:10].to_owned() + " – " + range.end[:10].to_owned(),
      { x: 7.2, y: 7.2 + header, width, height: line, },
      false,
      probe,
      profile,
    )
  }
  for (_, period, cell) in cells {
    let x = cell.x
    let bar_y = cell.y
    let cell_width = cell.width
    let bar_height = cell.height
    self.paint_text(
      primitives,
      period.label,
      { x, y: label_y, width: cell_width, height: self.size * 1.5, },
      false,
      probe,
      profile,
    )
    if bar_height <= 0 || cell_width <= 0 {
      continue
    }
    primitives.push(
      Rectangle({
        x,
        y: bar_y,
        width: cell_width,
        height: bar_height,
        color: color_tint(self.accent, 0.85),
      }),
    )
    if selection is Some((start, end)) {
      let start = start.max(period.first)
      let end = end.min(period.next)
      if start < end {
        let factor = column / (period.next - period.first)
        let left = ((start - period.first) * factor).min(cell_width)
        primitives.push(
          Rectangle({
            x: x + left,
            y: bar_y,
            width: ((end - start) * factor).min(cell_width - left),
            height: bar_height,
            color: self.accent,
          }),
        )
      }
    }
    primitives.push(Stroke(cell, "ffffff", 0.75))
  }
  if view.scrollbar && width > 0 {
    let y = (rect.height - 12).max(0)
    primitives.push(
      Rectangle({ x: 7.2, y, width, height: 5, color: "e0e0e0", }),
    )
    let thumb = (width * count.to_double() / (upper - lower + 1).to_double())
      .max(12)
      .min(width)
    let progress = (first - lower).to_double() /
      (upper - lower + 1 - count).max(1).to_double()
    primitives.push(
      Rectangle({
        x: 7.2 + (width - thumb) * progress.min(1),
        y,
        width: thumb,
        height: 5,
        color: self.accent,
      }),
    )
  }
  primitives.push(Restore)
  primitives.push(Restore)
}
