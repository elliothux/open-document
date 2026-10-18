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
fn Geometry::resize_swaps_axes(self : Geometry) -> Bool {
  let angle = self.rotation - (self.rotation / 360).floor() * 360
  // ONLYOFFICE ShapeForResizeInGroup exchanges local scales near quarter turns.
  (angle >= 45 && angle < 135) || (angle >= 225 && angle < 315)
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
  guard (box.width > 0 || width == 0) && (box.height > 0 || height == 0) else {
    @failure.reject(
      "invalid-transform", "A zero selection extent cannot expand",
    )
  }
  let sx = if box.width > 0 { width / box.width } else { 1.0 }
  let sy = if box.height > 0 { height / box.height } else { 1.0 }
  guard sx > 0 && sy > 0 else {
    @failure.reject("invalid-transform", "Selection scale must be positive")
  }
  let objects = original.objects.map(object => {
    if !self.selection.objects.contains(object.id) {
      return object
    }
    let g = object.geometry.unwrap()
    let width = g.width * (if g.resize_swaps_axes() { sy } else { sx })
    let height = g.height * (if g.resize_swaps_axes() { sx } else { sy })
    let next = {
      ..g,
      x: if sx == 1 && sy == 1 {
        g.x + (x - box.x)
      } else {
        x + (g.x + g.width / 2 - box.x) * sx - width / 2
      },
      y: if sx == 1 && sy == 1 {
        g.y + (y - box.y)
      } else {
        y + (g.y + g.height / 2 - box.y) * sy - height / 2
      },
      width,
      height,
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
  let mut minimum_x = 0.0
  let mut minimum_y = 0.0
  for object_id in self.selection.objects {
    let object = original.object(object_id)
    let g = object.geometry.unwrap()
    let (x, y) = if object.preset == "line" {
      let scale = 0.1 / (g.width + g.height)
      (scale, scale)
    } else if g.resize_swaps_axes() {
      (0.1 / g.height, 0.1 / g.width)
    } else {
      (0.1 / g.width, 0.1 / g.height)
    }
    minimum_x = minimum_x.max(x)
    minimum_y = minimum_y.max(y)
  }
  let width = if box.width == 0 {
    0.0
  } else {
    (box.width + (if left { -dx } else { dx })).max(box.width * minimum_x)
  }
  let height = if box.height == 0 {
    0.0
  } else {
    (box.height + (if top { -dy } else { dy })).max(box.height * minimum_y)
  }
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
