///|
priv struct DrawingGesture {
  id : Int32
  drawing : Int32
  initial : @layout.DrawingFrame
  preserve_aspect : Bool
  handle : Int32
  origin : @layout.DrawingAnchor?
  placement : (@layout.PageSetup, @layout.Layout)?
  prepared : PreparedEdit?
  probe : @layout.TextProbe?
  profile : Map[String, String]
  images : @layout.Images?
}

///|
fn Session::require_drawing_gesture(
  self : Session,
  revision : Int32,
  id : Int32,
) -> DrawingGesture raise @failure.Failure {
  self.check_revision_value(revision)
  guard self.drawing_gesture is Some(gesture) && gesture.id == id else {
    @failure.reject("stale-gesture", "Drawing gesture identity changed")
  }
  gesture
}

///|
/// Begins a tentative move (0) or corner resize (1–4), honoring native aspect locks.
pub fn Session::begin_drawing_gesture(
  self : Session,
  revision : Int32,
  drawing : Int32,
  handle : Int32,
  probe? : @layout.TextProbe,
  profile~ : Map[String, String] = Map([]),
  images? : @layout.Images,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  self.check_document_protection()
  guard handle >= 0 && handle <= 4 else {
    @failure.reject("invalid-operation", "Invalid drawing gesture handle")
  }
  let tree = WordTree::new(self.document())
  guard self.selected_drawing(tree) == Some(drawing) else {
    @failure.reject(
      "invalid-operation", "Select the drawing before starting a gesture",
    )
  }
  let initial = if handle == 0 {
    self.editable_drawing_position(tree, drawing).0
  } else if tree.drawing_data(drawing).1.attribute("uri") ==
    Some(word_shape_uri) {
    guard !tree.shape_locked(drawing, "noResize") else {
      @failure.reject("protected-content", "Shape resizing is locked")
    }
    self.editable_shape(tree, drawing).1
  } else if tree.drawing_data(drawing).1.attribute("uri") == Some(chart_uri) {
    ignore(self.editable_chart(tree, drawing, operation=ChartResize))
    self.drawing_frame(tree, drawing)
  } else {
    ignore(self.editable_picture(tree, drawing))
    self.drawing_frame(tree, drawing)
  }
  guard !(initial.content
    is (@layout.Shape(_) | @layout.TextBox(_, _) | @layout.Chart(_))) ||
    !tree.shape_locked(drawing, "noSelect") else {
    @failure.reject("protected-content", "Shape selection is locked")
  }
  let placement = if handle == 0 && probe is Some(probe) {
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
    Some((flow.page, layout))
  } else {
    None
  }
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
      guard placement is Some((setup, layout)) else {
        @failure.reject(
          "invalid-operation", "Moving aligned pictures requires a text probe",
        )
      }
      let selection = self.selection.unwrap()
      Some(
        layout.drawing_anchor_offsets(
          setup,
          selection.anchor.paragraph,
          selection.anchor.offset.min(selection.focus.offset),
        ),
      )
    }
  } else {
    None
  }
  guard self.drawing_gesture_id < 2147483647 else {
    @failure.reject("limit-exceeded", "Drawing gesture identity exhausted")
  }
  self.drawing_gesture_id += 1
  self.drawing_gesture = Some({
    id: self.drawing_gesture_id,
    drawing,
    initial,
    preserve_aspect: initial.content is @layout.Picture(_, _) ||
    tree.shape_locked(drawing, "noChangeAspect"),
    handle,
    origin,
    placement,
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
fn Session::prepare_drawing_gesture(
  self : Session,
  gesture : DrawingGesture,
  dx : Double,
  dy : Double,
  page : Int32?,
) -> PreparedEdit? raise @failure.Failure {
  guard !dx.is_nan() &&
    !dx.is_inf() &&
    !dy.is_nan() &&
    !dy.is_inf() &&
    dx.abs() <= 14400 &&
    dy.abs() <= 14400 else {
    @failure.reject("invalid-operation", "Invalid drawing gesture delta")
  }
  let image = gesture.initial
  let handle = gesture.handle
  if page is Some(page) {
    guard handle == 0 && gesture.placement is Some((setup, layout)) else {
      @failure.reject(
        "invalid-operation", "Page movement requires a floating move and text probe",
      )
    }
    let selection = self.selection.unwrap()
    let (anchor, hit) = layout.move_drawing(
      setup,
      selection.anchor.paragraph,
      selection.anchor.offset.min(selection.focus.offset),
      dx,
      dy,
      page,
    )
    let target = hit.map(hit => {
      paragraph: hit.paragraph,
      offset: hit.offset,
      affinity: hit.affinity,
      bidiLevel: None,
      frameStart: None,
    })
    let probe = gesture.probe
    let images = gesture.images
    return self.prepare_drawing_anchor(
      gesture.drawing,
      Some(anchor),
      target?,
      probe?,
      profile=gesture.profile,
      images?,
    )
  }
  if handle == 0 {
    let anchor = image.anchor.unwrap()
    let origin = gesture.origin.unwrap()
    fn shift(
      axis : @layout.DrawingAxis,
      initial : @layout.DrawingAxis,
      delta : Double,
    ) -> @layout.DrawingAxis raise @failure.Failure {
      if delta == 0 {
        return initial
      }
      match axis {
        @layout.Offset(reference, value) =>
          @layout.Offset(reference, value + delta)
        _ =>
          @failure.reject(
            "invalid-operation", "Drawing gesture has no resolved offset",
          )
      }
    }
    let probe = gesture.probe
    let images = gesture.images
    return self.prepare_drawing_anchor(
      gesture.drawing,
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
  if image.content
    is (@layout.Shape(_) | @layout.TextBox(_, _) | @layout.Chart(_)) {
    let (minimum_width, minimum_height) = match image.content {
      @layout.Chart(_) => (180.0, 150.0)
      @layout.Shape({ preset: "line", .. }) => (0.0, 0.0)
      _ => (1.0 / 12700, 1.0 / 12700)
    }
    let (width, height) = if gesture.preserve_aspect {
      let delta = if image.height == 0 || dy == 0 {
        if image.width == 0 {
          0.0
        } else {
          dx / image.width
        }
      } else if image.width == 0 || dx == 0 {
        dy / image.height
      } else {
        (dx / image.width).max(dy / image.height)
      }
      let positive = if image.width == 0 {
        image.height
      } else if image.height == 0 {
        image.width
      } else {
        image.width.min(image.height)
      }
      let factor = (1.0 + delta)
        .max(1.0 / 12700 / positive)
        .max(if image.width == 0 { 0 } else { minimum_width / image.width })
        .max(if image.height == 0 { 0 } else { minimum_height / image.height })
        .min(14400.0 / image.width.max(image.height))
      (image.width * factor, image.height * factor)
    } else {
      let width = (image.width + dx).max(minimum_width).min(14400)
      let height = (image.height + dy).max(minimum_height).min(14400)
      if width == 0 && height == 0 {
        if image.width > 0 {
          (1.0 / 12700, 0.0)
        } else {
          (0.0, 1.0 / 12700)
        }
      } else {
        (width, height)
      }
    }
    let prepared = match image.content {
      @layout.Shape(shape) | @layout.TextBox(shape, _) =>
        self.prepare_shape_edit(
          gesture.drawing,
          width,
          height,
          shape.fill,
          shape.stroke,
          shape.lineWidth,
        )
      @layout.Chart(_) =>
        self.prepare_chart_resize(gesture.drawing, width, height)
      _ => abort("Expected shape or chart")
    }
    if prepared is Some(prepared) {
      self.check_picture_layout(
        prepared.document,
        gesture.probe,
        gesture.profile,
        gesture.images,
      )
    }
    return prepared
  }
  guard image.content is @layout.Picture(_, crop) else {
    abort("Expected picture")
  }
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
    .min(1000000000.0 * (1.0 - crop[0] - crop[2]) / image.width)
    .min(1000000000.0 * (1.0 - crop[1] - crop[3]) / image.height)
  let factor = factor.max(0.1 / image.width.min(image.height)).min(maximum)
  let prepared = self.prepare_picture_resize(
    gesture.drawing,
    image.width * factor,
    image.height * factor,
    crop,
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
pub fn Session::update_drawing_gesture(
  self : Session,
  revision : Int32,
  id : Int32,
  dx : Double,
  dy : Double,
  page? : Int32,
) -> Json raise @failure.Failure {
  let gesture = self.require_drawing_gesture(revision, id)
  let prepared = self.prepare_drawing_gesture(gesture, dx, dy, page)
  if prepared is Some(prepared) {
    self.opc.validate_changes(self.replacements(prepared.document, self.parts))
  }
  self.drawing_gesture = Some({ ..gesture, prepared, })
  self.edit_result(prepared.map(p => p.edit.paragraphs).unwrap_or([]))
}

///|
/// Commits the authoritative final pointer position as at most one edit.
pub fn Session::finish_drawing_gesture(
  self : Session,
  revision : Int32,
  id : Int32,
  dx : Double,
  dy : Double,
  page? : Int32,
) -> Json raise @failure.Failure {
  let gesture = self.require_drawing_gesture(revision, id)
  let prepared = self.prepare_drawing_gesture(gesture, dx, dy, page)
  if prepared is Some(prepared) {
    self.commit_edit(prepared.edit, prepared.document)
  }
  self.drawing_gesture = None
  self.edit_result(prepared.map(p => p.edit.paragraphs).unwrap_or([]))
}

///|
/// Discards the candidate and preserves committed selection, revision and history.
pub fn Session::cancel_drawing_gesture(
  self : Session,
  revision : Int32,
  id : Int32,
) -> Json raise @failure.Failure {
  let gesture = self.require_drawing_gesture(revision, id)
  self.drawing_gesture = None
  self.edit_result(gesture.prepared.map(p => p.edit.paragraphs).unwrap_or([]))
}
