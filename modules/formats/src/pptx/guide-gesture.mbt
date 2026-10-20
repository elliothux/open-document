///|
priv struct GuideDrag {
  index : Int
  start : Double
  position : Double
}

///|
/// Begins a visible guide drag, or leaves the session unchanged when no guide is hit.
pub fn Session::begin_guide(
  self : Session,
  revision : Int,
  x : Double,
  y : Double,
  tolerance : Double,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  self.check_idle()
  guard [x, y, tolerance].all(value => !value.is_nan() && !value.is_inf()) &&
    x.abs() <= 14400 &&
    y.abs() <= 14400 &&
    tolerance >= 0 &&
    tolerance <= 64 else {
    @failure.reject("invalid-hit", "Invalid guide point or tolerance")
  }
  let reason = self.slide_visibility_reason()
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let (visible, guides) = self
    .guide_properties()
    .map(read_guides)
    .unwrap_or((false, []))
  if !visible {
    return self.query()
  }
  for index = guides.length() - 1; index >= 0; index = index - 1 {
    let guide = guides[index]
    let start = if guide.orientation == "horz" { y } else { x }
    if (guide.position - start).abs() <= tolerance {
      guard self.sequence < 2147483647 else {
        @failure.reject("limit-exceeded", "Gesture identity exhausted")
      }
      self.sequence += 1
      self.candidate = Some({
        id: self.sequence,
        revision,
        selection: self.selection,
        slide: self.current(),
        edit: None,
        kind: "guide",
        guide: Some({ index, start, position: guide.position, }),
        snap_lines: [],
      })
      return self.query()
    }
  }
  self.query()
}

///|
fn Session::drag_guide(
  self : Session,
  candidate : Candidate,
  drag : GuideDrag,
  dx : Double,
  dy : Double,
  handle : Int,
) -> Json raise @failure.Failure {
  guard handle == 0 else {
    @failure.reject(
      "invalid-transform", "Guide dragging does not use object handles",
    )
  }
  let (_, guides) = read_guides(self.guide_properties().unwrap())
  let guide = guides[drag.index]
  let horizontal = guide.orientation == "horz"
  let delta = if horizontal { dy } else { dx }
  // ONLYOFFICE tracks the pointer on the guide axis and clamps to the slide edge.
  let position = if delta == 0 {
    guide.position
  } else {
    ((drag.start + delta).clamp(
      min=0,
      max=if horizontal { self.height } else { self.width },
    ) *
    8).round() /
    8
  }
  self.candidate = Some({ ..candidate, guide: Some({ ..drag, position, }), })
  self.query()
}

///|
fn Session::commit_guide(
  self : Session,
  drag : GuideDrag,
) -> Json raise @failure.Failure {
  let (visible, guides) = read_guides(self.guide_properties().unwrap())
  guides[drag.index] = { ..guides[drag.index], position: drag.position, }
  self.set_guides(visible, guides)
}
