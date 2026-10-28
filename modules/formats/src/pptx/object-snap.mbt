///|
fn Session::snap_drag(
  self : Session,
  dx : Double,
  dy : Double,
  handle : Int32,
  tolerance : Double,
  center : Bool,
) -> (Double, Double, Array[Guide], (Bool, Bool), (Bool, Bool)) raise @failure.Failure {
  if tolerance == 0 || (dx == 0 && dy == 0) {
    return (dx, dy, [], (false, false), (false, false))
  }
  // Unknown view metadata stays intact and does not prevent independent object edits.
  let view = self.guide_properties() catch { _ => None }
  let guides = view.map(read_guides).unwrap_or((false, [])).1 catch { _ => [] }
  let snap_objects = view
    .map(tree => {
      guide_owner(tree)
      .map(owner => flag(owner, "snapToObjects", default=true))
      .unwrap_or(true)
    })
    .unwrap_or(true) catch {
      _ => false
    }
  let slide = self.source_slide(self.selection.slide)
  let (dx, dy, size) = if handle > 0 && snap_objects {
    self.snap_resize_size(slide, dx, dy, handle, tolerance, center)
  } else {
    (dx, dy, (false, false))
  }
  let moving = slide.snap_members(self.selection.objects)
  let targets_x : Array[(Double, Int32)] = []
  let targets_y : Array[(Double, Int32)] = []
  if snap_objects {
    for object in slide.objects {
      if object.source.tree.part == slide.tree.part &&
        object.kind != "group" &&
        !moving.contains(object.id) {
        for (x, y) in object.snap_points() {
          let order = targets_x.length()
          targets_x.push((x, order))
          targets_y.push((y, order))
        }
      }
    }
  }
  for guide in guides {
    let targets = if guide.orientation == "vert" {
      targets_x
    } else {
      targets_y
    }
    targets.push(
      (guide.position, slide.objects.length() * 5 + targets.length()),
    )
  }
  let targets_x = sorted_snap_targets(targets_x)
  let targets_y = sorted_snap_targets(targets_y)
  let grid = try {
    let value = read_snapping(view)
    if value.grid {
      Some(value.spacing)
    } else {
      None
    }
  } catch {
    _ => None
  }
  let points : Array[(Double, Double)] = []
  if handle > 0 {
    let left = handle == 1 || handle == 4
    let top = handle == 1 || handle == 2
    let object = slide.object(self.selection.object)
    if self.selection.objects.length() == 1 {
      let g = object.geometry.unwrap()
      points.push(
        g.matrix.point(
          if left {
            0
          } else {
            g.width
          },
          if top {
            0
          } else {
            g.height
          },
        ),
      )
    } else {
      let box = slide.selection_box(self.selection.objects, in_parent=true)
      points.push(
        object.source
        .parent_frame()
        .point(
          box.x + (if left { 0 } else { box.width }),
          box.y + (if top { 0 } else { box.height }),
        ),
      )
    }
  } else {
    for object in slide.objects {
      if object.kind != "group" && moving.contains(object.id) {
        points.append(object.snap_points())
      }
    }
  }
  let mut snap_x : Double? = None
  let mut snap_y : Double? = None
  let lines_x : Array[Double] = []
  let lines_y : Array[Double] = []
  let (dx, dy) = if handle > 0 && grid is Some(spacing) {
    let (x, y) = points[0]
    (
      if dx == 0 || size.0 {
        dx
      } else {
        nearest_grid_point(x + dx, self.width, spacing) - x
      },
      if dy == 0 || size.1 {
        dy
      } else {
        nearest_grid_point(y + dy, self.height, spacing) - y
      },
    )
  } else {
    (dx, dy)
  }
  for (x, y) in points {
    if dx != 0 && !size.0 {
      if nearest_snap_target(targets_x, x + dx) is Some((position, order)) {
        let distance = position - (x + dx)
        if distance.abs() <= tolerance {
          if snap_x is None || distance.abs() < snap_x.unwrap().abs() {
            if snap_x
              .map(previous => (previous - distance).abs() > 1.0 / 12700)
              .unwrap_or(true) {
              lines_x.clear()
            }
            snap_x = Some(distance)
          }
          if (snap_x.unwrap() - distance).abs() <= 1.0 / 12700 &&
            order < slide.objects.length() * 5 &&
            position >= 0 &&
            position <= self.width &&
            lines_x.length() < 64 &&
            !lines_x.contains(position) {
            lines_x.push(position)
          }
        }
      }
    }
    if dy != 0 && !size.1 {
      if nearest_snap_target(targets_y, y + dy) is Some((position, order)) {
        let distance = position - (y + dy)
        if distance.abs() <= tolerance {
          if snap_y is None || distance.abs() < snap_y.unwrap().abs() {
            if snap_y
              .map(previous => (previous - distance).abs() > 1.0 / 12700)
              .unwrap_or(true) {
              lines_y.clear()
            }
            snap_y = Some(distance)
          }
          if (snap_y.unwrap() - distance).abs() <= 1.0 / 12700 &&
            order < slide.objects.length() * 5 &&
            position >= 0 &&
            position <= self.height &&
            lines_y.length() < 64 &&
            !lines_y.contains(position) {
            lines_y.push(position)
          }
        }
      }
    }
  }
  let mut spacing_x = false
  let mut spacing_y = false
  if handle == 0 &&
    snap_objects &&
    ((dx != 0 && snap_x is None) || (dy != 0 && snap_y is None)) {
    let original = slide.selection_box(self.selection.objects)
    let box = {
      ..original,
      x: original.x + dx + snap_x.unwrap_or(0),
      y: original.y + dy + snap_y.unwrap_or(0),
    }
    let neighbors = self.spacing_neighbors(slide)
    if dx != 0 &&
      snap_x is None &&
      spacing_axis(box, neighbors, tolerance, true) is Some((target, _)) {
      snap_x = Some(target - box.x)
      spacing_x = true
    }
    if dy != 0 &&
      snap_y is None &&
      spacing_axis(box, neighbors, tolerance, false) is Some((target, _)) {
      snap_y = Some(target - box.y)
      spacing_y = true
    }
  }
  if handle == 0 && grid is Some(spacing) {
    let box = slide.selection_box([self.selection.object])
    if dx != 0 && snap_x is None {
      snap_x = Some(
        nearest_grid_point(box.x + dx, self.width, spacing) - box.x - dx,
      )
    }
    if dy != 0 && snap_y is None {
      snap_y = Some(
        nearest_grid_point(box.y + dy, self.height, spacing) - box.y - dy,
      )
    }
  }
  let lines : Array[Guide] = []
  for position in lines_x {
    lines.push({ orientation: "vert", position, })
  }
  for position in lines_y {
    lines.push({ orientation: "horz", position, })
  }
  (
    dx + snap_x.unwrap_or(0),
    dy + snap_y.unwrap_or(0),
    lines,
    (spacing_x, spacing_y),
    size,
  )
}

///|
fn Object::snap_points(self : Object) -> Array[(Double, Double)] {
  guard self.geometry is Some(g) else { return [] }
  // ONLYOFFICE uses transformed corners and centre, including each group leaf.
  [
    (0.0, 0.0),
    (g.width, 0.0),
    (g.width / 2, g.height / 2),
    (g.width, g.height),
    (0.0, g.height),
  ].map(point => g.matrix.point(point.0, point.1))
}

///|
fn sorted_snap_targets(
  targets : Array[(Double, Int32)],
) -> Array[(Double, Int32)] {
  targets.sort()
  let result : Array[(Double, Int32)] = []
  for target in targets {
    if result.last().map(previous => previous.0 != target.0).unwrap_or(true) {
      result.push(target)
    }
  }
  result
}

///|
fn nearest_snap_target(
  targets : Array[(Double, Int32)],
  value : Double,
) -> (Double, Int32)? {
  // Sorted targets keep large multi-selections from comparing every point pair.
  let index = match targets.binary_search((value, -1)) {
    Ok(index) | Err(index) => index
  }
  let next = targets.get(index)
  let previous = targets.get(index - 1)
  match (previous, next) {
    (Some(a), Some(b)) => {
      let da = a.0 - value
      let db = b.0 - value
      Some(
        if da.abs() < db.abs() || (da.abs() == db.abs() && a.1 < b.1) {
          a
        } else {
          b
        },
      )
    }
    (Some(a), None) | (None, Some(a)) => Some(a)
    _ => None
  }
}

///|
fn Slide::snap_members(self : Slide, ids : Array[String]) -> Map[String, Bool] {
  let parents : Map[String, String] = Map([])
  let selected : Map[String, Bool] = Map([])
  for id in ids {
    selected[id] = true
  }
  for object in self.objects {
    parents[object.id] = object.parent
  }
  let moving : Map[String, Bool] = Map([])
  for object in self.objects {
    let mut parent = object.id
    while !parent.is_empty() && !selected.contains(parent) {
      parent = parents.get(parent).unwrap_or("")
    }
    if !parent.is_empty() {
      moving[object.id] = true
    }
  }
  moving
}

///|
fn Session::drag_aligned(
  self : Session,
  query : Json,
  lines : Array[Guide],
  spacing : (Bool, Bool),
  size : (Bool, Bool),
) -> Json {
  self.candidate = Some({
    ..self.candidate.unwrap(),
    snap_lines: lines,
    snap_spacing: spacing,
    snap_size: size,
  })
  query
}

///|
fn Session::snap_lines(self : Session) -> Array[Json] raise @failure.Failure {
  guard self.candidate is Some(candidate) && !candidate.snap_lines.is_empty() else {
    return []
  }
  let slide = self.current()
  let moving = slide.snap_members(candidate.selection.objects)
  let xs : Array[(Double, Int32)] = []
  let ys : Array[(Double, Int32)] = []
  for object in slide.objects {
    if object.kind != "group" && moving.contains(object.id) {
      for (x, y) in object.snap_points() {
        let order = xs.length()
        xs.push((x, order))
        ys.push((y, order))
      }
    }
  }
  let xs = sorted_snap_targets(xs)
  let ys = sorted_snap_targets(ys)
  candidate.snap_lines
  .filter(line => {
    let targets = if line.orientation == "vert" { xs } else { ys }
    // Minimum sizes and preview constraints can prevent the requested snap.
    nearest_snap_target(targets, line.position)
    .map(target => (target.0 - line.position).abs() <= 1.0 / 12700)
    .unwrap_or(false)
  })
  .map(line => { "orientation": line.orientation, "position": line.position })
}

///|
pub fn Session::drag(
  self : Session,
  revision : Int32,
  id : Int32,
  dx : Double,
  dy : Double,
  handle : Int32,
  tolerance~ : Double = 0,
  shift~ : Bool = false,
  center~ : Bool = false,
) -> Json raise @failure.Failure {
  let candidate = self.gesture(revision, id)
  guard !dx.is_nan() &&
    !dx.is_inf() &&
    !dy.is_nan() &&
    !dy.is_inf() &&
    dx.abs() <= 14400 &&
    dy.abs() <= 14400 &&
    handle >= 0 &&
    handle <= 4 &&
    !tolerance.is_nan() &&
    !tolerance.is_inf() &&
    tolerance >= 0 &&
    tolerance <= 64 else {
    @failure.reject("invalid-transform", "Invalid drag delta or handle")
  }
  if candidate.kind == "connector" {
    return self.drag_connector(candidate, dx, dy, handle, tolerance)
  }
  if candidate.kind == "adjustment" {
    return self.drag_adjustment(candidate, dx, dy, handle)
  }
  if candidate.guide is Some(guide) {
    return self.drag_guide(candidate, guide, dx, dy, handle)
  }
  guard candidate.kind == "transform" else {
    @failure.reject("invalid-operation", "Not an object drag gesture")
  }
  let slide = self.source_slide(self.selection.slide)
  let object = slide.object(self.selection.object)
  let center = center &&
    handle > 0 &&
    !(self.selection.objects.length() == 1 && line_shape(object.preset))
  let aspect = handle > 0 &&
    (
      shift ||
      self.selection.objects.all(id => slide.object(id).kind == "image")
    )
  let (dx, dy, lines, spacing, size) = self.snap_drag(
    dx,
    dy,
    handle,
    if aspect {
      0
    } else {
      tolerance
    },
    center,
  )
  if self.selection.objects.length() > 1 {
    return self.drag_aligned(
      self.drag_collection(revision, id, dx, dy, handle, aspect, center),
      lines,
      spacing,
      size,
    )
  }
  let initial = object.geometry.unwrap()
  if handle == 0 {
    let inverse = object.source.parent_frame().inverse()
    return self.drag_aligned(
      self.transform(
        revision,
        id,
        initial.x + inverse.a * dx + inverse.c * dy,
        initial.y + inverse.b * dx + inverse.d * dy,
        initial.width,
        initial.height,
      ),
      lines,
      spacing,
      size,
    )
  }
  let inverse = initial.matrix.inverse()
  let local_x = inverse.a * dx + inverse.c * dy
  let local_y = inverse.b * dx + inverse.d * dy
  let left = handle == 1 || handle == 4
  let top = handle == 1 || handle == 2
  let factor = if center { 2.0 } else { 1.0 }
  let raw_width = initial.width +
    (if left { -local_x } else { local_x }) * factor
  let raw_height = initial.height +
    (if top { -local_y } else { local_y }) * factor
  let can_flip = (raw_width < 0 || raw_height < 0) &&
    self.object_edit_reason(object, "flip").is_empty()
  let flip_x = initial.flip_x != (can_flip && raw_width < 0)
  let flip_y = initial.flip_y != (can_flip && raw_height < 0)
  let minimum = if line_shape(object.preset) { 0.0 } else { 0.1 }
  let mut width = (if can_flip { raw_width.abs() } else { raw_width }).max(
    minimum,
  )
  let mut height = (if can_flip { raw_height.abs() } else { raw_height }).max(
    minimum,
  )
  if width + height < 0.1 {
    if initial.width > 0 {
      width = 0.1
    } else {
      height = 0.1
    }
  }
  let (width, height) = proportional_size(
    width,
    height,
    initial.width,
    initial.height,
    aspect,
  )
  let anchor_x = if center { 0.5 } else if left { 1.0 } else { 0.0 }
  let anchor_y = if center { 0.5 } else if top { 1.0 } else { 0.0 }
  let (fixed_x, fixed_y) = initial.matrix.point(
    initial.width * anchor_x,
    initial.height * anchor_y,
  )
  let (fixed_x, fixed_y) = object.source
    .parent_frame()
    .inverse()
    .point(fixed_x, fixed_y)
  let matrix = object_matrix(
    0,
    0,
    width,
    height,
    initial.rotation,
    flip_x,
    flip_y,
  )
  let (offset_x, offset_y) = matrix.point(width * anchor_x, height * anchor_y)
  self.drag_aligned(
    self.preview_transform(candidate, {
      ..initial,
      x: fixed_x - offset_x,
      y: fixed_y - offset_y,
      width,
      height,
      flip_x,
      flip_y,
    }),
    lines,
    spacing,
    size,
  )
}

///|
fn proportional_size(
  width : Double,
  height : Double,
  original_width : Double,
  original_height : Double,
  aspect : Bool,
) -> (Double, Double) {
  guard aspect && original_width > 0 && original_height > 0 else {
    return (width, height)
  }
  let scale = (width / original_width).max(height / original_height)
  (original_width * scale, original_height * scale)
}
