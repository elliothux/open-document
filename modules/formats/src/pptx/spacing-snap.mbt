///|
priv struct SpacingMark {
  axis : String
  from : Double
  to : Double
  at : Double
} derive(ToJson)

///|
priv struct SpacingSpan {
  start : Double
  end : Double
  first : Double
  last : Double
}

///|
fn spacing_span(box : SelectionBox, horizontal : Bool) -> SpacingSpan {
  if horizontal {
    {
      start: box.x,
      end: box.x + box.width,
      first: box.y,
      last: box.y + box.height,
    }
  } else {
    {
      start: box.y,
      end: box.y + box.height,
      first: box.x,
      last: box.x + box.width,
    }
  }
}

///|
fn spacing_axis(
  box : SelectionBox,
  neighbors : Array[SelectionBox],
  tolerance : Double,
  horizontal : Bool,
) -> (Double, Array[SpacingMark])? {
  let box = spacing_span(box, horizontal)
  let spans = neighbors
    .map(box => spacing_span(box, horizontal))
    .filter(other => box.first.max(other.first) < box.last.min(other.last))
  let mut left : Int? = None
  let mut right : Int? = None
  for i, span in spans {
    if span.end <= box.start + tolerance &&
      left.map(index => span.end > spans[index].end).unwrap_or(true) {
      left = Some(i)
    }
    if span.start >= box.end - tolerance &&
      right.map(index => span.start < spans[index].start).unwrap_or(true) {
      right = Some(i)
    }
  }
  let mark = fn(from : Double, to : Double, a : SpacingSpan, b : SpacingSpan) {
    SpacingMark::{
      axis: if horizontal {
        "x"
      } else {
        "y"
      },
      from,
      to,
      at: (a.first.max(b.first) + a.last.min(b.last)) / 2,
    }
  }
  let mut best : (Double, Array[SpacingMark])? = None
  let consider = fn(position : Double, marks : Array[SpacingMark]) {
    let distance = (position - box.start).abs()
    if distance <= tolerance &&
      best.map(old => distance < (old.0 - box.start).abs()).unwrap_or(true) {
      best = Some((position, marks))
    }
  }
  if left is Some(index) && right is Some(next) {
    let a = spans[index]
    let b = spans[next]
    let gap = (b.start - a.end - (box.end - box.start)) / 2
    if gap >= 0 {
      let target = a.end + gap
      consider(target, [
        mark(a.end, target, box, a),
        mark(target + box.end - box.start, b.start, box, b),
      ])
    }
  }
  if left is Some(index) {
    let near = spans[index]
    let mut beyond : Int? = None
    for i, span in spans {
      if i != index &&
        span.end <= near.start &&
        beyond.map(previous => span.end > spans[previous].end).unwrap_or(true) {
        beyond = Some(i)
      }
    }
    if beyond is Some(previous) {
      let far = spans[previous]
      let gap = near.start - far.end
      let target = near.end + gap
      consider(target, [
        mark(far.end, near.start, near, far),
        mark(near.end, target, box, near),
      ])
    }
  }
  if right is Some(index) {
    let near = spans[index]
    let mut beyond : Int? = None
    for i, span in spans {
      if i != index &&
        span.start >= near.end &&
        beyond
        .map(previous => span.start < spans[previous].start)
        .unwrap_or(true) {
        beyond = Some(i)
      }
    }
    if beyond is Some(next) {
      let far = spans[next]
      let gap = far.start - near.end
      let target = near.start - gap - (box.end - box.start)
      consider(target, [
        mark(target + box.end - box.start, near.start, box, near),
        mark(near.end, far.start, near, far),
      ])
    }
  }
  best
}

///|
fn Session::spacing_neighbors(
  self : Session,
  slide : Slide,
) -> Array[SelectionBox] raise @failure.Failure {
  let parent = slide.object(self.selection.object).parent
  let selected : Map[String, Bool] = Map([])
  for id in self.selection.objects {
    selected[id] = true
  }
  let neighbors : Array[SelectionBox] = []
  for object in slide.objects {
    if object.parent != parent ||
      selected.contains(object.id) ||
      object.source.tree.part != slide.tree.part {
      continue
    }
    let points = object.snap_points()
    if points.is_empty() {
      continue
    }
    let mut left = points[0].0
    let mut right = left
    let mut top = points[0].1
    let mut bottom = top
    for (x, y) in points {
      left = left.min(x)
      right = right.max(x)
      top = top.min(y)
      bottom = bottom.max(y)
    }
    neighbors.push({
      x: left,
      y: top,
      width: right - left,
      height: bottom - top,
    })
  }
  neighbors
}

///|
fn Session::snap_spacing(self : Session) -> Array[Json] raise @failure.Failure {
  guard self.candidate is Some(candidate) &&
    (candidate.snap_spacing.0 || candidate.snap_spacing.1) else {
    return []
  }
  let slide = self.current()
  let box = slide.selection_box(self.selection.objects)
  let neighbors = self.spacing_neighbors(slide)
  let marks : Array[Json] = []
  for horizontal in [true, false] {
    if !(if horizontal {
        candidate.snap_spacing.0
      } else {
        candidate.snap_spacing.1
      }) {
      continue
    }
    // Quantization and preview constraints must still leave the actual gaps equal.
    if spacing_axis(box, neighbors, 1.0 / 12700, horizontal)
      is Some((_, arrows)) &&
      arrows.all(mark => {
        mark.from >= 0 &&
        mark.to >= mark.from &&
        mark.to <= (if horizontal { self.width } else { self.height }) &&
        mark.at >= 0 &&
        mark.at <= (if horizontal { self.height } else { self.width })
      }) {
      marks.append(arrows.map(mark => Json(mark)))
    }
  }
  marks
}
