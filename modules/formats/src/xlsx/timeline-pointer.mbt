///|
/// Previews or commits a continuous date-bar selection using the measured native timeline.
pub fn Session::timeline_gesture(
  self : Session,
  revision : Int,
  layout : Int,
  id : String,
  handle : Int,
  first : Int,
  x : Double,
  y : Double,
  commit : Bool,
  probe : @layout.TextProbe,
  profile : Map[String, String],
  images~ : @layout.Images,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let grid = self.drawing_grid(layout)
  guard [x, y].all(value => {
      !value.is_nan() && !value.is_inf() && value.abs() <= 14400
    }) &&
    grid.objects.iter().find_first(object => object.id == id) is Some(object) &&
    object.timeline is Some(timeline) else {
    @failure.reject("invalid-operation", "Invalid timeline pointer target")
  }
  object.check_change(false, analysis_frame=true)
  let geometry = timeline.geometry(object.rect.width, object.rect.height)
  let visible = geometry.cells.filter(cell => {
    !grid.slicer_regions(object, cell.2).is_empty()
  })
  guard (handle == 0 && visible.any(cell => cell.0 == first)) ||
    (
      (handle == 1 || handle == 2) &&
      geometry.handles.any(item => {
        item.0 == handle &&
        item.1 == first &&
        !grid.slicer_regions(object, item.3).is_empty()
      })
    ) else {
    @failure.reject(
      "invalid-operation", "Timeline period is outside the visible control",
    )
  }
  let mut last = first
  let mut distance = 1000000000000.0
  for (index, _, rect) in visible {
    for region in grid.slicer_regions(object, rect) {
      guard region
        is {
          "clip": {
            "x": Number(left, ..),
            "y": Number(top, ..),
            "width": Number(width, ..),
            "height": Number(height, ..),
            ..
          },
          ..
        } else {
        continue
      }
      let dx = (left - x).max(0).max(x - left - width)
      let dy = (top - y).max(0).max(y - top - height)
      let next = dx * dx + dy * dy
      if next < distance || (next == distance && index == first) {
        last = index
        distance = next
      }
    }
  }
  let view = if commit {
    self
  } else {
    { ..self, history: [], redo: [], history_bytes: 0, }
  }
  let query = if handle == 0 {
    let bounds = timeline.control.cache.state.bounds
    let lower = timeline_period(first.min(last), timeline.control.level)
    let upper = timeline_period(first.max(last), timeline.control.level)
    let minimum = pivot_date_parse(bounds.start, false)
    let start = if lower.first <= minimum {
      bounds.start
    } else {
      pivot_date_text(lower.first, false)
    }
    let end = timeline_period_end(upper, bounds, self.date1904)
    view.apply_timeline_filter(
      revision,
      grid.sheet,
      timeline.control.name,
      Some((start, end)),
      view_changes=[("selectionLevel", timeline.control.level.to_string())],
    )
  } else {
    view.set_timeline_endpoint(
      revision,
      grid.sheet,
      timeline.control.name,
      handle,
      timeline.control.level,
      last,
    )
  }
  let drawing = if commit {
    Json::null()
  } else {
    view.viewport(
      grid.sheet,
      grid.scroll_x,
      grid.scroll_y,
      grid.width,
      grid.height,
      probe,
      profile,
      images~,
    )
  }
  if !commit {
    self.grid_id = view.grid_id
  }
  { "query": if commit { query } else { Json::null() }, "drawing": drawing }
}
