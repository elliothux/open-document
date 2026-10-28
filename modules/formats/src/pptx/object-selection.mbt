///|
fn Session::transform_objects(
  self : Session,
  action~ : String = "arrange",
) -> Array[Object] raise @failure.Failure {
  guard self.selection.mode == "object" && !self.selection.objects.is_empty() else {
    @failure.reject("invalid-operation", "Select objects before transforming")
  }
  let slide = self.current()
  let objects = self.selection.objects.map(id => {
    let object = slide.object(id)
    let reason = self.object_edit_reason(object, action)
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
  guard objects.all(object => object.parent == objects[0].parent) else {
    @failure.reject("protected-content", "Select objects from one parent group")
  }
  objects
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
  in_parent~ : Bool = false,
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
        let matrix = if in_parent {
          object_matrix(
            g.x,
            g.y,
            g.width,
            g.height,
            g.rotation,
            g.flip_x,
            g.flip_y,
          )
        } else {
          g.matrix
        }
        let (x, y) = matrix.point(x, y)
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
  flip_x~ : Bool = false,
  flip_y~ : Bool = false,
) -> Json raise @failure.Failure {
  let original = self.source_slide(self.selection.slide)
  let box = original.selection_box(self.selection.objects, in_parent=true)
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
      x: if sx == 1 && sy == 1 && !flip_x && !flip_y {
        g.x + (x - box.x)
      } else {
        x +
        (if flip_x {
          box.width - (g.x + g.width / 2 - box.x)
        } else {
          g.x + g.width / 2 - box.x
        }) *
        sx -
        width / 2
      },
      y: if sx == 1 && sy == 1 && !flip_x && !flip_y {
        g.y + (y - box.y)
      } else {
        y +
        (if flip_y {
          box.height - (g.y + g.height / 2 - box.y)
        } else {
          g.y + g.height / 2 - box.y
        }) *
        sy -
        height / 2
      },
      width,
      height,
      rotation: if flip_x != flip_y {
        -g.rotation
      } else {
        g.rotation
      },
      flip_x: g.flip_x != flip_x,
      flip_y: g.flip_y != flip_y,
    }
    if flip_x || flip_y {
      let reason = self.object_edit_reason(object, "flip")
      guard reason.is_empty() else {
        @failure.reject("protected-content", reason)
      }
    }
    validate_object_box(
      next.x,
      next.y,
      next.width,
      next.height,
      line_shape(object.preset),
    )
    {
      ..object,
      table: object.table.map(table => table.resized(width, height)),
      geometry: Some(object.placed_geometry(next)),
    }
  })
  let preview = original
    .group_preview(objects)
    .group_bounds(
      self.selection.objects.filter(id => {
        member_geometry_changed(
          original.object(id).geometry.unwrap(),
          objects.iter().find_first(o => o.id == id).unwrap().geometry.unwrap(),
        )
      }),
    )
    .connector_bounds(original)
  ignore(self.tile_sizes(preview))
  self.candidate = Some({
    ..candidate,
    slide: preview,
    snap_lines: [],
    snap_spacing: (false, false),
    snap_size: (false, false),
  })
  self.view = None
  self.query()
}

///|
fn Session::drag_collection(
  self : Session,
  revision : Int32,
  id : Int32,
  dx : Double,
  dy : Double,
  handle : Int32,
  aspect : Bool,
  center : Bool,
) -> Json raise @failure.Failure {
  let original = self.source_slide(self.selection.slide)
  let box = original.selection_box(self.selection.objects, in_parent=true)
  let inverse = original.object(self.selection.object).source
    .parent_frame()
    .inverse()
  let (dx, dy) = (
    inverse.a * dx + inverse.c * dy,
    inverse.b * dx + inverse.d * dy,
  )
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
  let factor = if center { 2.0 } else { 1.0 }
  let mut minimum_x = 0.0
  let mut minimum_y = 0.0
  for object_id in self.selection.objects {
    let object = original.object(object_id)
    let g = object.geometry.unwrap()
    let (x, y) = if line_shape(object.preset) {
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
  let raw_width = if box.width == 0 {
    0.0
  } else {
    box.width + (if left { -dx } else { dx }) * factor
  }
  let raw_height = if box.height == 0 {
    0.0
  } else {
    box.height + (if top { -dy } else { dy }) * factor
  }
  let can_flip = (raw_width < 0 || raw_height < 0) &&
    self.selection.objects.all(id => {
      self.object_edit_reason(original.object(id), "flip").is_empty()
    })
  let flip_x = can_flip && raw_width < 0
  let flip_y = can_flip && raw_height < 0
  let width = if box.width == 0 {
    0.0
  } else {
    (if can_flip { raw_width.abs() } else { raw_width }).max(
      box.width * minimum_x,
    )
  }
  let height = if box.height == 0 {
    0.0
  } else {
    (if can_flip { raw_height.abs() } else { raw_height }).max(
      box.height * minimum_y,
    )
  }
  let (width, height) = proportional_size(
    width,
    height,
    box.width,
    box.height,
    aspect,
  )
  self.transform_collection(
    self.gesture(revision, id),
    if center {
      box.x + (box.width - width) / 2
    } else if left {
      box.x + box.width - (if flip_x { 0 } else { width })
    } else {
      box.x - (if flip_x { width } else { 0 })
    },
    if center {
      box.y + (box.height - height) / 2
    } else if top {
      box.y + box.height - (if flip_y { 0 } else { height })
    } else {
      box.y - (if flip_y { height } else { 0 })
    },
    width,
    height,
    flip_x~,
    flip_y~,
  )
}
