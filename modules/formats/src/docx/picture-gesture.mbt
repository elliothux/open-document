///|
priv struct PictureGesture {
  id : Int
  picture : Int
  initial : @layout.ImageFrame
  handle : Int
  origin : @layout.ImageAnchor?
  prepared : PreparedEdit?
  probe : @layout.TextProbe?
  profile : Map[String, String]
  images : @layout.Images?
}

///|
fn Session::require_picture_gesture(
  self : Session,
  revision : Int,
  id : Int,
) -> PictureGesture raise @failure.Failure {
  self.check_revision_value(revision)
  guard self.picture_gesture is Some(gesture) && gesture.id == id else {
    @failure.reject("stale-gesture", "Picture gesture identity changed")
  }
  gesture
}

///|
/// Begins a tentative move (handle 0) or aspect-preserving corner resize (1–4).
pub fn Session::begin_picture_gesture(
  self : Session,
  revision : Int,
  picture : Int,
  handle : Int,
  probe? : @layout.TextProbe,
  profile~ : Map[String, String] = Map([]),
  images? : @layout.Images,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  self.check_document_protection()
  guard handle >= 0 && handle <= 4 else {
    @failure.reject("invalid-operation", "Invalid picture gesture handle")
  }
  let tree = WordTree::new(self.document())
  guard self.selected_picture(tree) == Some(picture) else {
    @failure.reject(
      "invalid-operation", "Select the picture before starting a gesture",
    )
  }
  let initial = self.editable_picture(tree, picture, position=handle == 0).0
  let origin = if handle == 0 {
    guard initial.anchor is Some(anchor) else {
      @failure.reject(
        "invalid-operation", "Only floating body pictures can move",
      )
    }
    if anchor.horizontal is @layout.Offset(_, _) &&
      anchor.vertical is @layout.Offset(_, _) {
      Some(anchor)
    } else {
      guard probe is Some(probe) else {
        @failure.reject(
          "invalid-operation", "Moving aligned pictures requires a text probe",
        )
      }
      let flow = self.flow()
      let layout = @layout.paginate(
        probe,
        flow,
        profile,
        images.unwrap_or(@layout.Images::new()),
      )
      guard layout.diagnostics.is_empty() else {
        @failure.reject(
          "unsupported-layout", "Picture movement requires supported document layout",
        )
      }
      let selection = self.selection.unwrap()
      Some(
        layout.image_anchor_offsets(
          flow.page,
          selection.anchor.paragraph,
          selection.anchor.offset.min(selection.focus.offset),
        ),
      )
    }
  } else {
    None
  }
  guard self.picture_gesture_id < 2147483647 else {
    @failure.reject("limit-exceeded", "Picture gesture identity exhausted")
  }
  self.picture_gesture_id += 1
  self.picture_gesture = Some({
    id: self.picture_gesture_id,
    picture,
    initial,
    handle,
    origin,
    prepared: None,
    probe,
    profile: profile.copy(),
    images,
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
  gesture : PictureGesture,
  dx : Double,
  dy : Double,
) -> PreparedEdit? raise @failure.Failure {
  guard !dx.is_nan() &&
    !dx.is_inf() &&
    !dy.is_nan() &&
    !dy.is_inf() &&
    dx.abs() <= 14400 &&
    dy.abs() <= 14400 else {
    @failure.reject("invalid-operation", "Invalid picture gesture delta")
  }
  let image = gesture.initial
  let handle = gesture.handle
  if handle == 0 {
    let anchor = image.anchor.unwrap()
    let origin = gesture.origin.unwrap()
    fn shift(
      axis : @layout.ImageAxis,
      initial : @layout.ImageAxis,
      delta : Double,
    ) -> @layout.ImageAxis raise @failure.Failure {
      if delta == 0 {
        return initial
      }
      match axis {
        @layout.Offset(reference, value) =>
          @layout.Offset(reference, value + delta)
        _ =>
          @failure.reject(
            "invalid-operation", "Picture gesture has no resolved offset",
          )
      }
    }
    let probe = gesture.probe
    let images = gesture.images
    return self.prepare_picture_anchor(
      gesture.picture,
      Some({
        ..anchor,
        horizontal: shift(origin.horizontal, anchor.horizontal, dx),
        vertical: shift(origin.vertical, anchor.vertical, dy),
      }),
      probe?,
      profile=gesture.profile,
      images?,
    )
  }
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
  let prepared = self.prepare_picture_resize(
    gesture.picture,
    image.width * factor,
    image.height * factor,
    image.crop,
  )
  if prepared is Some(prepared) {
    self.check_picture_layout(
      prepared.document,
      gesture.probe,
      gesture.profile,
      gesture.images,
    )
  }
  prepared
}

///|
/// Replaces the candidate from the original frame without changing source history.
pub fn Session::update_picture_gesture(
  self : Session,
  revision : Int,
  id : Int,
  dx : Double,
  dy : Double,
) -> Json raise @failure.Failure {
  let gesture = self.require_picture_gesture(revision, id)
  let prepared = self.prepare_picture_gesture(gesture, dx, dy)
  if prepared is Some(prepared) {
    self.opc.validate_changes(self.replacements(prepared.document, self.parts))
  }
  self.picture_gesture = Some({ ..gesture, prepared, })
  self.edit_result(prepared.map(p => p.edit.paragraphs).unwrap_or([]))
}

///|
/// Commits the authoritative final pointer position as at most one edit.
pub fn Session::finish_picture_gesture(
  self : Session,
  revision : Int,
  id : Int,
  dx : Double,
  dy : Double,
) -> Json raise @failure.Failure {
  let gesture = self.require_picture_gesture(revision, id)
  let prepared = self.prepare_picture_gesture(gesture, dx, dy)
  if prepared is Some(prepared) {
    self.commit_edit(prepared.edit, prepared.document)
  }
  self.picture_gesture = None
  self.edit_result(prepared.map(p => p.edit.paragraphs).unwrap_or([]))
}

///|
/// Discards the candidate and preserves committed selection, revision and history.
pub fn Session::cancel_picture_gesture(
  self : Session,
  revision : Int,
  id : Int,
) -> Json raise @failure.Failure {
  let gesture = self.require_picture_gesture(revision, id)
  self.picture_gesture = None
  self.edit_result(gesture.prepared.map(p => p.edit.paragraphs).unwrap_or([]))
}
