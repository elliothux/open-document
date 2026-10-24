///|
/// Previews or commits an ordered member range using the native visible slicer geometry.
pub fn Session::slicer_gesture(
  self : Session,
  revision : Int,
  layout : Int,
  id : String,
  first : Int,
  position : Int,
  x : Double,
  y : Double,
  additive : Bool,
  commit : Bool,
  probe : @layout.TextProbe,
  profile : Map[String, String],
  images~ : @layout.Images,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let grid = self.drawing_grid(layout)
  let (_, object, slicer, geometry) = self.slicer_target(
    revision,
    grid.sheet,
    layout,
    id,
  )
  guard [x, y].all(value => {
      !value.is_nan() && !value.is_inf() && value.abs() <= 14400
    }) &&
    position >= 0 &&
    position <= 4095 else {
    @failure.reject("invalid-operation", "Invalid slicer gesture position")
  }
  object.check_change(false, analysis_frame=true)
  let members = slicer.control.cache.members
  guard geometry.buttons
    .iter()
    .find_first(pair => members[pair.0].index == first)
    is Some((anchor, rect)) &&
    !grid.slicer_regions(object, rect, clip=geometry.body).is_empty() else {
    @failure.reject(
      "invalid-operation", "Slicer gesture must start at a visible member",
    )
  }
  let start = position.min(geometry.maximum / slicer.control.columns) *
    slicer.control.columns
  let projected = { ..slicer, control: { ..slicer.control, start, }, }
  if commit {
    projected.paint([], object.rect, probe, profile)
  }
  let visible = projected.geometry(
    object.rect.width,
    object.rect.height,
    probe,
    profile,
  )
  let mut last = anchor
  let mut distance = 1000000000000.0
  for (index, rect) in visible.buttons {
    for region in grid.slicer_regions(object, rect, clip=visible.body) {
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
      if next < distance || (next == distance && index == anchor) {
        last = index
        distance = next
      }
    }
  }
  let indices = members
    .mapi((index, item) => (index, item))
    .filter_map(pair => {
      let (index, item) = pair
      let inside = index >= anchor.min(last) && index <= anchor.max(last)
      if (if inside {
          !additive || !item.selected
        } else {
          additive && item.selected
        }) {
        Some(item.index)
      } else {
        None
      }
    })
  let key = (grid.sheet, slicer.control.name)
  guard start == slicer.control.start ||
    self.slicer_scrolls.contains(key) ||
    self.slicer_scrolls.length() < 4096 else {
    @failure.reject("limit-exceeded", "Slicer view state exceeds budget")
  }
  let view = if commit {
    self
  } else {
    {
      ..self,
      history: [],
      redo: [],
      history_bytes: 0,
      slicer_scrolls: self.slicer_scrolls.copy(),
    }
  }
  let query = if indices.is_empty() {
    view.query()
  } else {
    view.filter_slicer(revision, grid.sheet, slicer.control.name, indices)
  }
  if start != slicer.control.start {
    view.slicer_scrolls[key] = start
    if commit {
      view.grid = None
    }
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
