///|
fn Session::connector_for_gesture(
  self : Session,
) -> Object raise @failure.Failure {
  guard self.selection.mode == "object" && self.selection.objects.length() == 1 else {
    @failure.reject(
      "invalid-operation", "Select one connector before dragging an endpoint",
    )
  }
  let object = self
    .source_slide(self.selection.slide)
    .object(self.selection.object)
  let reason = self.object_edit_reason(object, "endpoints")
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  ignore(object.connector_ends())
  object
}

///|
fn Slide::snap_connector(
  self : Slide,
  x : Double,
  y : Double,
  tolerance : Double,
  owner~ : String = "",
) -> ConnectorEnd raise @failure.Failure {
  // ONLYOFFICE ResizeTrackShapeImage searches topmost drawings, then native site order.
  for target in self.objects.rev() {
    if target.source.tree.part != self.tree.part || target.parent != owner {
      continue
    }
    for site in 0..<target.connection_site_count() {
      let (px, py) = target.connection_point(site)
      let dx = px - x
      let dy = py - y
      if dx * dx + dy * dy < tolerance * tolerance {
        return { x: px, y: py, target: target.id, site, }
      }
    }
  }
  { x, y, target: "", site: 0, }
}

///|
fn Session::drag_connector(
  self : Session,
  candidate : Candidate,
  dx : Double,
  dy : Double,
  handle : Int,
  tolerance : Double,
) -> Json raise @failure.Failure {
  guard [1, 2].contains(handle) else {
    @failure.reject("invalid-transform", "Select a connector endpoint handle")
  }
  let object = self.connector_for_gesture()
  let original = self.source_slide(self.selection.slide)
  let (start, end) = object.connector_ends()
  let point = if handle == 1 { start } else { end }
  guard (point.x + dx).abs() <= 14400 && (point.y + dy).abs() <= 14400 else {
    @failure.reject(
      "invalid-transform", "Connector endpoint exceeds coordinate budget",
    )
  }
  let point = if dx == 0 && dy == 0 {
    point
  } else {
    original.snap_connector(
      point.x + dx,
      point.y + dy,
      tolerance,
      owner=object.parent,
    )
  }
  let start = if handle == 1 { point } else { start }
  let end = if handle == 2 { point } else { end }
  let changes = object.connector_changes(start, end)
  let (slide, edit) = if changes.is_empty() {
    (original, None)
  } else {
    let (slide, edit) = self.prepare(original, changes)
    (slide, Some(edit))
  }
  self.candidate = Some({ ..candidate, slide, edit, })
  self.view = None
  self.query()
}
