///|
pub(all) struct SlideAdvance {
  click : Bool
  after : Int32?
} derive(Eq)

///|
pub extend SlideAdvance with Eq::{equal, not_equal}

///|
fn SlideAdvance::validate(self : SlideAdvance) -> Unit raise @failure.Failure {
  if self.after is Some(after) && (after < 0 || after > 3600000) {
    @failure.reject(
      "invalid-operation", "Slide advance must be within one hour",
    )
  }
}

///|
fn read_slide_advance(tree : Tree) -> SlideAdvance raise @failure.Failure {
  let value : SlideAdvance = if tree.one(
      tree.root("sld").id,
      "transition",
      uri=presentation_uri,
    )
    is Some(node) {
    {
      click: flag(node, "advClick", default=true),
      after: node
      .attribute("advTm")
      .map(text => number(text, 0, 3600000).to_int()),
    }
  } else {
    { click: true, after: None, }
  }
  value.validate()
  value
}

///|
fn SlideAdvance::json(self : SlideAdvance) -> Json {
  {
    "click": self.click,
    "after": self.after.map(v => Json(v)).unwrap_or(Json::null()),
  }
}

///|
fn Session::set_advance(
  self : Session,
  index : Int32,
  value : SlideAdvance,
) -> Json raise @failure.Failure {
  value.validate()
  let tree = self.slides[index].tree
  let transition = read_slide_transition(tree)
  if read_slide_advance(tree) == value {
    return self.query()
  }
  self.write_transition(index, transition, value)
}

///|
fn Session::show_tick(
  self : Session,
  current : ShowState,
) -> ShowState? raise @failure.Failure {
  let mut current = current
  // Bound zero-duration loops to one route per tick.
  for _ in 0..<current.route.length() {
    guard !current.paused &&
      !current.animations_running() &&
      current.step == current.animations.length() &&
      current.advance.after is Some(after) else {
      return Some(current)
    }
    let deadline = (current.settled + after.to_double()).max(current.ready)
    if current.elapsed < deadline {
      return Some(current)
    }
    guard self.show_neighbor(current, true) is Some(next) else { return None }
    let remaining = current.elapsed - deadline
    current = self
      .show_scene(
        current.route,
        next,
        current.custom,
        Some(current.index),
        current.time - remaining,
        true,
        leaving=current.animation_state(),
        last_view=Some((current.route, current.position, current.custom)),
      )
      .advance(current.time)
  }
  Some(current)
}
