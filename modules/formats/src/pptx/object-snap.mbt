///|
fn Session::snap_drag(
  self : Session,
  dx : Double,
  dy : Double,
  handle : Int,
  tolerance : Double,
) -> (Double, Double, Array[Guide]) raise @failure.Failure {
  if tolerance == 0 || (dx == 0 && dy == 0) {
    return (dx, dy, [])
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
  let moving = slide.snap_members(self.selection.objects)
  let targets_x : Array[(Double, Int)] = []
  let targets_y : Array[(Double, Int)] = []
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
      if dx == 0 {
        0.0
      } else {
        nearest_grid_point(x + dx, self.width, spacing) - x
      },
      if dy == 0 {
        0.0
      } else {
        nearest_grid_point(y + dy, self.height, spacing) - y
      },
    )
  } else {
    (dx, dy)
  }
  for (x, y) in points {
    if dx != 0 {
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
    if dy != 0 {
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
  (dx + snap_x.unwrap_or(0), dy + snap_y.unwrap_or(0), lines)
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
fn sorted_snap_targets(targets : Array[(Double, Int)]) -> Array[(Double, Int)] {
  targets.sort()
  let result : Array[(Double, Int)] = []
  for target in targets {
    if result.last().map(previous => previous.0 != target.0).unwrap_or(true) {
      result.push(target)
    }
  }
  result
}

///|
fn nearest_snap_target(
  targets : Array[(Double, Int)],
  value : Double,
) -> (Double, Int)? {
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
) -> Json {
  self.candidate = Some({ ..self.candidate.unwrap(), snap_lines: lines, })
  query
}

///|
fn Session::snap_lines(self : Session) -> Array[Json] raise @failure.Failure {
  guard self.candidate is Some(candidate) && !candidate.snap_lines.is_empty() else {
    return []
  }
  let slide = self.current()
  let moving = slide.snap_members(candidate.selection.objects)
  let xs : Array[(Double, Int)] = []
  let ys : Array[(Double, Int)] = []
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
