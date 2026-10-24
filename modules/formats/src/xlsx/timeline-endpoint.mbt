///|
fn SheetTimeline::selected_range(self : SheetTimeline) -> TimelineRange? {
  match self.cache.state.selection {
    Some(range) => Some(range)
    None if self.cache.state.filterType == "unknown" =>
      Some(self.cache.state.bounds)
    _ => None
  }
}

///|
fn timeline_period_end(
  period : TimelinePeriod,
  bounds : TimelineRange,
  date1904 : Bool,
) -> String raise @failure.Failure {
  if period.next > pivot_date_parse(bounds.end, false) {
    return bounds.end
  }
  let next = period.next +
    (pivot_date_epoch(false) - pivot_date_epoch(date1904)).to_double()
  // Midnight belongs only to the next period, including sub-millisecond native dates.
  pivot_date_text(
    (next.reinterpret_as_int64() - 1).reinterpret_as_double(),
    date1904,
  )
}

///|
/// Moves one native range endpoint, retaining the opposite timestamp and following it in the measured view.
pub fn Session::set_timeline_endpoint(
  self : Session,
  revision : Int,
  sheet : String,
  name : String,
  handle : Int,
  level : Int,
  position : Int,
) -> Json raise @failure.Failure {
  let view = self.timeline_view_target(revision, sheet, name)
  guard (handle == 1 || handle == 2) && level == view.level else {
    @failure.reject(
      "invalid-operation", "Invalid timeline endpoint or changed display level",
    )
  }
  let bounds = view.cache.state.bounds
  let minimum = pivot_date_parse(bounds.start, false)
  let maximum = pivot_date_parse(bounds.end, false)
  guard position >= timeline_period_key(minimum, level) &&
    position <= timeline_period_key(maximum, level) else {
    @failure.reject(
      "invalid-operation", "Timeline endpoint period is outside available dates",
    )
  }
  let range = view
    .selected_range()
    .unwrap_or_else(() => {
      @failure.reject(
        "protected-content", "Timeline has no continuous selected range",
      )
    })
  let original = timeline_period_key(
    pivot_date_parse(if handle == 1 { range.start } else { range.end }, false),
    level,
  )
  let fixed = timeline_period_key(
    pivot_date_parse(if handle == 1 { range.end } else { range.start }, false),
    level,
  )
  let position = if handle == 1 {
    position.min(fixed)
  } else {
    position.max(fixed)
  }
  if position == original {
    return self.query()
  }
  let period = timeline_period(position, level)
  let start = if handle == 2 {
    range.start
  } else if period.first <= minimum {
    bounds.start
  } else {
    pivot_date_text(period.first, false)
  }
  let end = if handle == 1 {
    range.end
  } else {
    timeline_period_end(period, bounds, self.date1904)
  }
  let changes = [("selectionLevel", level.to_string())]
  if self.grid is Some(grid) &&
    grid.revision == revision &&
    grid.sheet == sheet &&
    grid.objects
    .iter()
    .find_first(object => {
      object.timeline
      .map(timeline => timeline.control.name == name)
      .unwrap_or(false)
    })
    is Some(object) &&
    object.timeline is Some(timeline) {
    let visible = timeline.geometry(object.rect.width, object.rect.height).cells.filter(cell => {
        !grid.slicer_regions(object, cell.2).is_empty()
      },
    )
    if visible.get(0).map(cell => position < cell.0).unwrap_or(false) ||
      visible.last().map(cell => position > cell.0).unwrap_or(false) {
      changes.push(
        (
          "scrollPosition",
          if period.first <= minimum {
            bounds.start
          } else {
            pivot_date_text(period.first.min(maximum), false)
          },
        ),
      )
    }
  }
  self.apply_timeline_filter(
    revision,
    sheet,
    name,
    Some((start, end)),
    view_changes=changes,
    retained=Some(range),
  )
}
