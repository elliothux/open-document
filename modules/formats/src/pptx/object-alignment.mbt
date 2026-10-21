///|
fn Session::position_objects(
  self : Session,
  change : ObjectEdit,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let slide = self.current()
  let objects = self.transform_objects()
  let (horizontal, relative, factor, distribute) = match change {
    Align(alignment, relative) => {
      guard ["left", "center", "right", "top", "middle", "bottom"].contains(
          alignment,
        ) &&
        ["slide", "selection", "active"].contains(relative) else {
        @failure.reject("invalid-operation", "Invalid object alignment")
      }
      (
        ["left", "center", "right"].contains(alignment),
        relative,
        if ["left", "top"].contains(alignment) {
          0.0
        } else if ["center", "middle"].contains(alignment) {
          0.5
        } else {
          1.0
        },
        false,
      )
    }
    Distribute(axis, relative) => {
      guard ["horizontal", "vertical"].contains(axis) &&
        ["slide", "selection"].contains(relative) else {
        @failure.reject("invalid-operation", "Invalid object distribution")
      }
      guard objects.length() >= (if relative == "selection" { 3 } else { 2 }) else {
        @failure.reject(
          "invalid-operation", "Distribution requires at least two page objects or three selected objects",
        )
      }
      (axis == "horizontal", relative, 0.0, true)
    }
    _ =>
      @failure.reject(
        "invalid-operation", "Unknown object positioning operation",
      )
  }
  let measure = fn(box : SelectionBox) {
    if horizontal {
      (box.x, box.width)
    } else {
      (box.y, box.height)
    }
  }
  let bounds = objects.mapi((index, object) => {
    (object, slide.selection_box([object.id]), index)
  })
  let mut gap = 0.0
  let mut position = 0.0
  if distribute {
    bounds.sort_by((a, b) => {
      let (a_pos, a_size) = measure(a.1)
      let (b_pos, b_size) = measure(b.1)
      let a_center = a_pos + a_size / 2
      let b_center = b_pos + b_size / 2
      if a_center == b_center {
        a.2.compare(b.2)
      } else {
        a_center.compare(b_center)
      }
    })
    let total = bounds
      .iter()
      .fold(init=0.0, (sum, object) => sum + measure(object.1).1)
    if relative == "selection" {
      let (start, _) = measure(bounds[0].1)
      let (end, size) = measure(bounds.last().unwrap().1)
      position = start
      gap = (end + size - start - total) / (bounds.length() - 1).to_double()
    } else {
      let extent = if horizontal { self.width } else { self.height }
      if total < extent {
        gap = (extent - total) / (bounds.length() + 1).to_double()
        position = gap
      } else {
        gap = (extent - total) / (bounds.length() - 1).to_double()
      }
    }
  } else {
    let target = match relative {
      "slide" => { x: 0.0, y: 0.0, width: self.width, height: self.height, }
      "selection" => slide.selection_box(self.selection.objects)
      _ => slide.selection_box([self.selection.object])
    }
    let (start, size) = measure(target)
    position = start + size * factor
  }
  let changes : Array[@xml.SourceChange] = []
  for (object, box, _) in bounds {
    let (start, size) = measure(box)
    let delta = if distribute {
      position - start
    } else {
      position - start - size * factor
    }
    let geometry = object.geometry.unwrap()
    let inverse = object.source.parent_frame().inverse()
    let dx = if horizontal { delta } else { 0.0 }
    let dy = if horizontal { 0.0 } else { delta }
    let target = {
      ..geometry,
      x: ((geometry.x + inverse.a * dx + inverse.c * dy) * 12700).round() /
      12700,
      y: ((geometry.y + inverse.b * dx + inverse.d * dy) * 12700).round() /
      12700,
    }
    validate_object_box(
      target.x,
      target.y,
      target.width,
      target.height,
      line_shape(object.preset),
    )
    if delta != 0 && (target.x != geometry.x || target.y != geometry.y) {
      changes.append(transform_changes(object, target))
    }
    if distribute {
      position += size + gap
    }
  }
  changes
}
