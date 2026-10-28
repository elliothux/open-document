///|
/// Updates the authoritative selection without changing document history.
pub fn Session::navigate(
  self : Session,
  revision : Int32,
  layout : @layout.Layout,
  layout_id : Int32,
  direction : String,
  extend_selection~ : Bool,
) -> @layout.Hit raise @failure.Failure {
  self.check_revision(revision)
  guard layout.revision == revision else {
    @failure.reject(
      "stale-layout", "Navigation layout has a different revision",
    )
  }
  guard ["left", "right", "up", "down", "home", "end"].contains(direction) else {
    @failure.reject("invalid-operation", "Unknown navigation direction")
  }
  guard self.selection is Some(selection) else {
    @failure.reject("invalid-position", "Select a document position first")
  }
  self.check_position(selection.anchor)
  self.check_position(selection.focus)
  let anchor = selection.anchor
  let focus = selection.focus
  let origin = layout.caret(
    focus.paragraph,
    focus.offset,
    focus.affinity,
    bidi_level?=focus.bidiLevel,
    frame_start?=focus.frameStart,
  )
  let vertical = direction == "up" || direction == "down"
  let goal = if vertical && self.navigation_layout == layout_id {
    self.vertical_x.unwrap_or(origin.x)
  } else {
    origin.x
  }
  let order = if anchor.paragraph == focus.paragraph {
    anchor.offset.compare(focus.offset)
  } else {
    layout.compare_positions(
      (anchor.paragraph, anchor.offset),
      (focus.paragraph, focus.offset),
    )
  }
  let hit = if !extend_selection &&
    order != 0 &&
    (direction == "left" || direction == "right") {
    let start = if order < 0 { anchor } else { focus }
    let end = if order < 0 { focus } else { anchor }
    let edge = if direction == "left" { start } else { end }
    layout.caret(
      edge.paragraph,
      edge.offset,
      edge.affinity,
      bidi_level?=edge.bidiLevel,
      frame_start?=edge.frameStart,
    )
  } else {
    layout.move_caret(
      (focus.paragraph, focus.offset, focus.affinity),
      direction,
      goal_x=goal,
      bidi_level?=focus.bidiLevel,
      frame_start?=focus.frameStart,
    )
  }
  guard hit.reason.is_empty() else {
    @failure.reject("protected-content", hit.reason)
  }
  let target : Position = {
    paragraph: hit.paragraph,
    offset: hit.offset,
    affinity: hit.affinity,
    bidiLevel: hit.bidiLevel,
    frameStart: hit.frameStart,
  }
  ignore(
    self.select(revision, {
      anchor: if extend_selection {
        anchor
      } else {
        target
      },
      focus: target,
    }),
  )
  if vertical {
    self.vertical_x = Some(goal)
    self.navigation_layout = layout_id
  }
  hit
}
