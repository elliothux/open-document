///|
priv struct PictureResize {
  id : Int
  picture : Int
  initial : @layout.InlineImage
  prepared : PreparedEdit?
}

///|
fn Session::picture_resize_gesture(
  self : Session,
  revision : Int,
  id : Int,
) -> PictureResize raise @failure.Failure {
  self.check_revision_value(revision)
  guard self.picture_resize is Some(gesture) && gesture.id == id else {
    @failure.reject("stale-gesture", "Picture resize identity changed")
  }
  gesture
}

///|
/// Begins a tentative resize of the exactly selected inline picture.
pub fn Session::begin_picture_resize(
  self : Session,
  revision : Int,
  picture : Int,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let tree = WordTree::new(self.document())
  guard self.selected_picture(tree) == Some(picture) else {
    @failure.reject(
      "invalid-operation", "Select the inline picture before resizing",
    )
  }
  let initial = self.editable_picture(tree, picture).0
  guard self.picture_resize_id < 2147483647 else {
    @failure.reject("limit-exceeded", "Picture resize identity exhausted")
  }
  self.picture_resize_id += 1
  self.picture_resize = Some({
    id: self.picture_resize_id,
    picture,
    initial,
    prepared: None,
  })
  self.input_group = None
  self.typing_text = None
  self.vertical_x = None
  self.navigation_layout = -1
  self.edit_state()
}

///|
fn Session::prepare_picture_gesture(
  self : Session,
  gesture : PictureResize,
  dx : Double,
  dy : Double,
  handle : Int,
) -> PreparedEdit? raise @failure.Failure {
  guard !dx.is_nan() &&
    !dx.is_inf() &&
    !dy.is_nan() &&
    !dy.is_inf() &&
    dx.abs() <= 14400 &&
    dy.abs() <= 14400 &&
    handle >= 1 &&
    handle <= 4 else {
    @failure.reject(
      "invalid-operation", "Invalid picture resize delta or corner",
    )
  }
  let image = gesture.initial
  let dx = if handle == 1 || handle == 4 { -dx } else { dx }
  let dy = if handle == 1 || handle == 2 { -dy } else { dy }
  // An untouched axis does not constrain keyboard resizing.
  let delta = if dy == 0 {
    dx / image.width
  } else if dx == 0 {
    dy / image.height
  } else {
    (dx / image.width).max(dy / image.height)
  }
  let factor = 1.0 + delta
  let maximum = (14400.0 / image.width.max(image.height))
    .min(1000000000.0 * (1.0 - image.crop[0] - image.crop[2]) / image.width)
    .min(1000000000.0 * (1.0 - image.crop[1] - image.crop[3]) / image.height)
  let factor = factor.max(0.1 / image.width.min(image.height)).min(maximum)
  self.prepare_picture_resize(
    gesture.picture,
    image.width * factor,
    image.height * factor,
    image.crop,
  )
}

///|
/// Replaces the candidate from original dimensions without changing source history.
pub fn Session::update_picture_resize(
  self : Session,
  revision : Int,
  id : Int,
  dx : Double,
  dy : Double,
  handle : Int,
) -> Json raise @failure.Failure {
  let gesture = self.picture_resize_gesture(revision, id)
  let prepared = self.prepare_picture_gesture(gesture, dx, dy, handle)
  if prepared is Some(prepared) {
    self.opc.validate_changes(self.replacements(prepared.document, self.parts))
  }
  self.picture_resize = Some({ ..gesture, prepared, })
  self.edit_result(prepared.map(p => p.edit.paragraphs).unwrap_or([]))
}

///|
/// Commits the authoritative final pointer position as at most one edit.
pub fn Session::finish_picture_resize(
  self : Session,
  revision : Int,
  id : Int,
  dx : Double,
  dy : Double,
  handle : Int,
) -> Json raise @failure.Failure {
  let gesture = self.picture_resize_gesture(revision, id)
  let prepared = self.prepare_picture_gesture(gesture, dx, dy, handle)
  if prepared is Some(prepared) {
    self.commit_edit(prepared.edit, prepared.document)
  }
  self.picture_resize = None
  self.edit_result(prepared.map(p => p.edit.paragraphs).unwrap_or([]))
}

///|
/// Discards the candidate and preserves committed selection, revision and history.
pub fn Session::cancel_picture_resize(
  self : Session,
  revision : Int,
  id : Int,
) -> Json raise @failure.Failure {
  let gesture = self.picture_resize_gesture(revision, id)
  self.picture_resize = None
  self.edit_result(gesture.prepared.map(p => p.edit.paragraphs).unwrap_or([]))
}
