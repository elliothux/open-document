///|
fn Session::transform_objects(
  self : Session,
) -> Array[Object] raise @failure.Failure {
  guard self.selection.mode == "object" && !self.selection.objects.is_empty() else {
    @failure.reject("invalid-operation", "Select objects before transforming")
  }
  let slide = self.current()
  self.selection.objects.map(id => {
    let object = slide.object(id)
    let reason = self.object_edit_reason(object, "arrange")
    guard reason.is_empty() && object.geometry is Some(_) else {
      @failure.reject(
        "protected-content",
        if reason.is_empty() {
          "Missing object geometry"
        } else {
          reason
        },
      )
    }
    object
  })
}

///|
priv struct SelectionBox {
  x : Double
  y : Double
  width : Double
  height : Double
}

///|
fn Slide::selection_box(
  self : Slide,
  ids : Array[String],
) -> SelectionBox raise @failure.Failure {
  let mut left = 0.0
  let mut top = 0.0
  let mut right = 0.0
  let mut bottom = 0.0
  let mut initialized = false
  for id in ids {
    if self.object(id).geometry is Some(g) {
      for
        (x, y) in [
          (0.0, 0.0),
          (g.width, 0.0),
          (g.width, g.height),
          (0.0, g.height),
        ] {
        let (x, y) = g.matrix.point(x, y)
        left = if initialized { left.min(x) } else { x }
        top = if initialized { top.min(y) } else { y }
        right = if initialized { right.max(x) } else { x }
        bottom = if initialized { bottom.max(y) } else { y }
        initialized = true
      }
    }
  }
  { x: left, y: top, width: right - left, height: bottom - top, }
}

///|
fn Session::transform_collection(
  self : Session,
  candidate : Candidate,
  x : Double,
  y : Double,
  width : Double,
  height : Double,
) -> Json raise @failure.Failure {
  let original = self.slides[self.index(self.selection.slide)]
  let box = original.selection_box(self.selection.objects)
  guard [x, y, width, height].all(v => {
      !v.is_nan() && !v.is_inf() && v.abs() <= 14400
    }) &&
    width >= 0 &&
    height >= 0 else {
    @failure.reject("invalid-transform", "Invalid selection bounds")
  }
  let scale = if box.width > 0 {
    width / box.width
  } else {
    height / box.height
  }
  // shortcut: Keep multi-object resizing proportional until skew transforms are supported.
  guard scale > 0 &&
    (width - box.width * scale).abs() < 0.000001 &&
    (height - box.height * scale).abs() < 0.000001 else {
    @failure.reject(
      "invalid-transform", "Multi-object resizing must preserve proportions",
    )
  }
  let objects = original.objects.map(object => {
    if !self.selection.objects.contains(object.id) {
      return object
    }
    let g = object.geometry.unwrap()
    let next = {
      ..g,
      x: if scale == 1 {
        g.x + (x - box.x)
      } else {
        x + (g.x - box.x) * scale
      },
      y: if scale == 1 {
        g.y + (y - box.y)
      } else {
        y + (g.y - box.y) * scale
      },
      width: g.width * scale,
      height: g.height * scale,
    }
    validate_object_box(
      next.x,
      next.y,
      next.width,
      next.height,
      object.preset == "line",
    )
    {
      ..object,
      geometry: Some({
        ..next,
        matrix: object_matrix(
          next.x,
          next.y,
          next.width,
          next.height,
          next.rotation,
          next.flip_x,
          next.flip_y,
        ),
      }),
    }
  })
  let preview = original.group_preview(objects)
  ignore(self.tile_sizes(preview))
  self.candidate = Some({ ..candidate, slide: preview, })
  self.view = None
  self.query()
}

///|
fn Session::drag_collection(
  self : Session,
  revision : Int,
  id : Int,
  dx : Double,
  dy : Double,
  handle : Int,
) -> Json raise @failure.Failure {
  let original = self.slides[self.index(self.selection.slide)]
  let box = original.selection_box(self.selection.objects)
  if handle == 0 {
    return self.transform(
      revision,
      id,
      box.x + dx,
      box.y + dy,
      box.width,
      box.height,
    )
  }
  let left = handle == 1 || handle == 4
  let top = handle == 1 || handle == 2
  let vx = if left { -box.width } else { box.width }
  let vy = if top { -box.height } else { box.height }
  let mut minimum = 0.0
  for object_id in self.selection.objects {
    let object = original.object(object_id)
    let g = object.geometry.unwrap()
    minimum = minimum.max(
      if object.preset == "line" {
        0.1 / (g.width + g.height)
      } else {
        (0.1 / g.width).max(0.1 / g.height)
      },
    )
  }
  let scale = (1.0 + (dx * vx + dy * vy) / (vx * vx + vy * vy)).max(minimum)
  let width = box.width * scale
  let height = box.height * scale
  self.transform(
    revision,
    id,
    if left {
      box.x + box.width - width
    } else {
      box.x
    },
    if top {
      box.y + box.height - height
    } else {
      box.y
    },
    width,
    height,
  )
}
