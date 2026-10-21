///|
fn Foundation::hit_result(
  self : Foundation,
  session : @docx.Session,
  hit : @layout.Hit,
) -> Json raise @failure.Failure {
  let position : @docx.Position = {
    paragraph: hit.paragraph,
    offset: hit.offset,
    affinity: hit.affinity,
    bidiLevel: hit.bidiLevel,
    frameStart: hit.frameStart,
  }
  let reason = if !hit.reason.is_empty() {
    hit.reason
  } else {
    try {
      session.check_position(position)
      ""
    } catch {
      @failure.Failure(code="protected-content", message~, ..) => message
      error => raise error
    }
  }
  let logical : Json = if reason.is_empty() {
    position.to_json()
  } else {
    Json::null()
  }
  let drawing : Json = if hit.drawingStart is Some(start) && reason.is_empty() {
    let selection : @docx.Selection = {
      anchor: {
        ..position,
        offset: start,
        affinity: "after",
        frameStart: None,
      },
      focus: {
        ..position,
        offset: start + 1,
        affinity: "before",
        frameStart: None,
      },
    }
    session.check_position(selection.anchor)
    session.check_position(selection.focus)
    Json(selection)
  } else {
    Json::null()
  }
  {
    "layoutId": self.layout_id,
    "revision": self.layout.unwrap().revision,
    "page": hit.page,
    "line": hit.line,
    "position": logical,
    "drawing": drawing,
    "editable": reason.is_empty(),
    "reason": reason,
    "x": hit.x,
    "y": hit.y,
    "height": hit.height,
  }
}
