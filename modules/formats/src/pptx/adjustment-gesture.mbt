///|
priv struct AdjustmentHandle {
  name : String
  value : Double
  maximum : Double
  x : Double
  y : Double
  dx : Double
  dy : Double
}

///|
fn Object::adjustment_handles(self : Object) -> Array[AdjustmentHandle] {
  guard self.geometry is Some(g) && g.width > 0 && g.height > 0 else {
    return []
  }
  let w = g.width
  let h = g.height
  let side = w.min(h)
  let (_, _, branch_head) = branched_arrow_adjustments(self.adjustments)
  let (elbow_shaft, elbow_head, _) = elbow_arrow_adjustments(
    self.preset,
    self.adjustments,
  )
  let elbow_left = w - side * (elbow_head + elbow_shaft / 2)
  let head = (side * self.adjustments.1)
    .max(0)
    .min((if vertical_arrow_shape(self.preset) { h } else { w }) / 2)
  self
  .adjustment_values()
  .map(item => {
    // ONLYOFFICE preset XY handles vary one guide linearly on its declared local axis.
    let (x, y, dx, dy) = match (self.preset, item.0) {
      ("bentConnector3" | "curvedConnector3", "adj1") => (0.0, h / 2, w, 0.0)
      (
        "bentConnector4"
        | "bentConnector5"
        | "curvedConnector4"
        | "curvedConnector5",
        "adj1",
      ) => (0.0, h * self.adjustments.1 / 2, w, 0.0)
      ("bentConnector4" | "curvedConnector4", "adj2") =>
        (w * (1 + self.adjustments.0) / 2, 0.0, 0.0, h)
      ("bentConnector5" | "curvedConnector5", "adj2") =>
        (w * (self.adjustments.0 + self.adjustments.2) / 2, 0.0, 0.0, h)
      ("bentConnector5" | "curvedConnector5", "adj3") =>
        (0.0, h * (1 + self.adjustments.1) / 2, w, 0.0)
      ("rightArrow", "adj1") => (0.0, h / 2, 0.0, -h / 2)
      ("notchedRightArrow", "adj1") => (w, h / 2, 0.0, -h / 2)
      ("leftArrow", "adj1") => (w, h / 2, 0.0, -h / 2)
      ("upArrow", "adj1") => (w / 2, h, -w / 2, 0.0)
      ("downArrow", "adj1") => (w / 2, 0.0, -w / 2, 0.0)
      ("leftRightArrow", "adj1") => (w - head, h / 2, 0.0, -h / 2)
      ("upDownArrow", "adj1") => (w / 2, h - head, -w / 2, 0.0)
      ("rightArrow" | "notchedRightArrow", "adj2") => (w, 0.0, -side, 0.0)
      ("leftArrow", "adj2") => (0.0, 0.0, side, 0.0)
      ("upArrow", "adj2") => (0.0, 0.0, 0.0, side)
      ("downArrow", "adj2") => (0.0, h, 0.0, -side)
      ("leftRightArrow", "adj2") => (0.0, 0.0, side, 0.0)
      ("upDownArrow", "adj2") => (0.0, 0.0, 0.0, side)
      ("quadArrow" | "leftRightUpArrow", "adj1") =>
        (w / 2, side * branch_head, -side / 2, 0.0)
      ("quadArrow" | "leftRightUpArrow", "adj2") => (w / 2, 0.0, -side, 0.0)
      ("quadArrow" | "leftRightUpArrow", "adj3") => (w, 0.0, 0.0, side)
      ("leftUpArrow", "adj1") =>
        (elbow_left, h - side * elbow_head, 0.0, -side / 2)
      ("leftUpArrow" | "bentUpArrow", "adj2") => (w, 0.0, -2 * side, 0.0)
      ("leftUpArrow" | "bentUpArrow", "adj3") => (elbow_left, 0.0, 0.0, side)
      ("bentUpArrow", "adj1") => (0.0, h, 0.0, -side)
      (
        "snip1Rect"
        | "snip2SameRect"
        | "round1Rect"
        | "round2SameRect",
        "adj"
        | "adj1",
      ) => (w, 0.0, -side, 0.0)
      ("snip2DiagRect" | "round2DiagRect" | "snipRoundRect", "adj1") =>
        (0.0, 0.0, side, 0.0)
      ("snip2DiagRect" | "round2DiagRect" | "snipRoundRect", "adj2") =>
        (w, 0.0, -side, 0.0)
      ("snip2SameRect" | "round2SameRect", "adj2") => (0.0, h, side, 0.0)
      ("triangle", _) => (0.0, 0.0, w, 0.0)
      ("chevron" | "homePlate", _) => (w, 0.0, -side, 0.0)
      ("star5", _) => (w / 2, h / 2 * 1.10557, 0.0, -h * 1.10557)
      ("star7", _) => (w / 2, h / 2 * 1.05210, 0.0, -h * 1.05210)
      (
        "star4"
        | "star6"
        | "star8"
        | "star10"
        | "star12"
        | "star16"
        | "star24"
        | "star32",
        _,
      ) => (w / 2, h / 2, 0.0, -h)
      _ => (0.0, 0.0, side, 0.0)
    }
    {
      name: item.0,
      value: item.1,
      maximum: item.2,
      x: x + dx * item.1,
      y: y + dy * item.1,
      dx,
      dy,
    }
  })
}

///|
fn Session::adjustment_object(self : Session) -> Object raise @failure.Failure {
  guard self.selection.mode == "object" && self.selection.objects.length() == 1 else {
    @failure.reject(
      "invalid-operation", "Select one shape before dragging an adjustment",
    )
  }
  let object = self
    .source_slide(self.selection.slide)
    .object(self.selection.object)
  let reason = self.adjustment_reason(object)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  object
}

///|
fn Session::drag_adjustment(
  self : Session,
  candidate : Candidate,
  dx : Double,
  dy : Double,
  handle : Int,
) -> Json raise @failure.Failure {
  let object = self.adjustment_object()
  let handles = object.adjustment_handles()
  guard handle >= 1 && handle <= handles.length() else {
    @failure.reject("invalid-transform", "Select a shape adjustment handle")
  }
  let knob = handles[handle - 1]
  let inverse = object.geometry.unwrap().matrix.inverse()
  let (x, y) = (
    inverse.a * dx + inverse.c * dy,
    inverse.b * dx + inverse.d * dy,
  )
  let delta = (knob.dx * x + knob.dy * y) /
    (knob.dx * knob.dx + knob.dy * knob.dy)
  let original = self.source_slide(self.selection.slide)
  let base = { ..self, candidate: None, }
  let changes = if delta == 0 {
    []
  } else {
    base.adjust_shape(
      knob.name,
      Some((knob.value + delta).max(0).min(knob.maximum)),
    )
  }
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

///|
fn Session::finish_adjustment(
  self : Session,
  candidate : Candidate,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> (Slide, @xml.Edit)? raise @failure.Failure {
  guard candidate.edit is Some(_) else { return None }
  let original = self.source_slide(self.selection.slide)
  let base = { ..self, candidate: None, }
  let changes : Array[@xml.SourceChange] = []
  let initial = original.object(self.selection.object)
  let changed = candidate.slide.object(self.selection.object)
  let raw = fn(object : Object, name : String) {
    match name {
      "adj2" => object.adjustments.1
      "adj3" => object.adjustments.2
      _ => object.adjustments.0
    }
  }
  for (name, _, _) in changed.adjustment_values() {
    // Coupled guide limits change effective values without changing their source guides.
    if raw(initial, name) != raw(changed, name) {
      changes.append(base.adjust_shape(name, Some(raw(changed, name))))
    }
  }
  if changes.is_empty() {
    None
  } else {
    Some(
      self.prepare_fitted(
        original,
        changes,
        self.selection.objects,
        probe,
        profile,
      ),
    )
  }
}

///|
fn Session::adjustment_geometry(
  self : Session,
) -> Array[Json] raise @failure.Failure {
  guard self.selection.mode == "object" && self.selection.objects.length() == 1 else {
    return []
  }
  let object = self.current().object(self.selection.object)
  guard self.adjustment_reason(object).is_empty() else { return [] }
  let matrix = object.geometry.unwrap().matrix
  object
  .adjustment_handles()
  .map(handle => {
    let (x, y) = matrix.point(handle.x, handle.y)
    { "name": handle.name, "x": x, "y": y }
  })
}
