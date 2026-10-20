///|
fn Session::snap_drag_to_guides(
  self : Session,
  dx : Double,
  dy : Double,
  handle : Int,
  tolerance : Double,
) -> (Double, Double) raise @failure.Failure {
  if tolerance == 0 || (dx == 0 && dy == 0) {
    return (dx, dy)
  }
  // Unknown view metadata stays intact and does not prevent independent object edits.
  let guides = self.guide_properties().map(read_guides).unwrap_or((false, [])).1 catch {
      _ => return (dx, dy)
    }
  if guides.is_empty() {
    return (dx, dy)
  }
  let slide = self.source_slide(self.selection.slide)
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
    let parents : Map[String, String] = Map([])
    let selected : Map[String, Bool] = Map([])
    for id in self.selection.objects {
      selected[id] = true
    }
    for object in slide.objects {
      parents[object.id] = object.parent
    }
    for object in slide.objects {
      if object.kind == "group" || object.geometry is None {
        continue
      }
      let mut parent = object.id
      while !parent.is_empty() && !selected.contains(parent) {
        parent = parents.get(parent).unwrap_or("")
      }
      if parent.is_empty() {
        continue
      }
      let g = object.geometry.unwrap()
      // ONLYOFFICE uses each leaf's four transformed corners and centre, including groups.
      for
        (x, y) in [
          (0.0, 0.0),
          (g.width, 0.0),
          (g.width / 2, g.height / 2),
          (g.width, g.height),
          (0.0, g.height),
        ] {
        points.push(g.matrix.point(x, y))
      }
    }
  }
  let mut snap_x : Double? = None
  let mut snap_y : Double? = None
  for (x, y) in points {
    for guide in guides {
      if guide.orientation == "vert" && dx != 0 {
        let distance = guide.position - x - dx
        if distance.abs() <= tolerance &&
          (snap_x is None || distance.abs() < snap_x.unwrap().abs()) {
          snap_x = Some(distance)
        }
      } else if guide.orientation == "horz" && dy != 0 {
        let distance = guide.position - y - dy
        if distance.abs() <= tolerance &&
          (snap_y is None || distance.abs() < snap_y.unwrap().abs()) {
          snap_y = Some(distance)
        }
      }
    }
  }
  (dx + snap_x.unwrap_or(0), dy + snap_y.unwrap_or(0))
}
