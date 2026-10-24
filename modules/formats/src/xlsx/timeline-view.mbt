///|
fn Session::timeline_view_target(
  self : Session,
  revision : Int,
  sheet : String,
  name : String,
) -> SheetTimeline raise @failure.Failure {
  self.check_revision(revision)
  let current = self.sheets[self.sheet_index(sheet)]
  guard self.read_only.is_empty() &&
    !current.locked &&
    current.state == "visible" else {
    @failure.reject(
      "protected-content", "Timeline worksheet is protected or hidden",
    )
  }
  self
  .read_timelines(sheet)
  .iter()
  .find_first(view => view.name == name)
  .unwrap_or_else(() => {
    @failure.reject(
      "invalid-operation", "Timeline view is outside this worksheet",
    )
  })
}

///|
fn Session::commit_timeline_view(
  self : Session,
  view : SheetTimeline,
  attribute : String,
  value : String,
) -> Json raise @failure.Failure {
  let document = self.part_xml(view.part)
  let tree = Tree::new(document)
  let node = tree
    .timeline_children(0, "timeline")
    .iter()
    .find_first(node => slicer_text(node, "name") == view.name)
    .unwrap()
  let changes = metadata_changes(node, [(attribute, value)])
  if changes.is_empty() {
    return self.query()
  }
  let (document, edit) = document.edit_source(changes)
  let parts = self.parts.copy()
  parts[view.part] = document
  let anchor = self.anchor
  let focus = self.focus
  self.commit(
    self.sheets,
    self.workbook,
    self.calculation.unwrap(),
    [(view.part, edit)],
    self.selection,
    parts~,
    drawing_selection=self.drawing_selection,
  )
  self.anchor = anchor
  self.focus = focus
  self.query()
}

///|
/// Changes the native display grain while retaining its absolute scroll and selected range.
pub fn Session::set_timeline_level(
  self : Session,
  revision : Int,
  sheet : String,
  name : String,
  level : Int,
) -> Json raise @failure.Failure {
  let view = self.timeline_view_target(revision, sheet, name)
  guard level >= 0 && level <= 3 else {
    @failure.reject("invalid-operation", "Invalid timeline display level")
  }
  if view.level == level {
    return self.query()
  }
  self.commit_timeline_view(view, "level", level.to_string())
}

///|
/// Saves the first visible period without filtering or refreshing connected pivot caches.
pub fn Session::scroll_timeline(
  self : Session,
  revision : Int,
  sheet : String,
  name : String,
  level : Int,
  position : Int,
) -> Json raise @failure.Failure {
  let view = self.timeline_view_target(revision, sheet, name)
  guard level == view.level else {
    @failure.reject("invalid-operation", "Timeline display level changed")
  }
  let bounds = view.cache.state.bounds
  let minimum = pivot_date_parse(bounds.start, false)
  let maximum = pivot_date_parse(bounds.end, false)
  let lower = timeline_period_key(minimum, view.level)
  let upper = timeline_period_key(maximum, view.level)
  guard position >= lower && position <= upper else {
    @failure.reject(
      "invalid-operation", "Timeline scroll period is outside its bounds",
    )
  }
  let current = view.scroll
    .map(value => pivot_date_parse(value, false))
    .unwrap_or(minimum)
    .max(minimum)
    .min(maximum)
  if timeline_period_key(current, view.level) == position {
    return self.query()
  }
  let first = timeline_period(position, view.level).first
  let value = if first <= minimum {
    bounds.start
  } else {
    pivot_date_text(first, false)
  }
  self.commit_timeline_view(view, "scrollPosition", value)
}
