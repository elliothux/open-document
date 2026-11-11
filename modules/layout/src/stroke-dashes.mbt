///|
fn canvas_dash_value(value : Double) -> Double {
  // Chromium stores the Canvas dash list and offset as single-precision values.
  Float::from_double(value).to_double()
}

///|
fn straight_dash_pieces(
  path : Array[PathSegment],
  style : DrawStyle,
  available : Int32,
) -> Array[Array[(Double, Double)]]? {
  let pattern = style.dash.map(canvas_dash_value)
  let phase = canvas_dash_value(style.dashOffset)
  guard !pattern.is_empty() &&
    pattern.all(value => value > 0 && !value.is_inf()) &&
    !phase.is_inf() &&
    !phase.is_nan() else {
    return None
  }
  let dash = if pattern.length() % 2 == 0 {
    pattern
  } else {
    [..pattern, ..pattern]
  }
  let total = dash.fold(init=0.0, (sum, value) => sum + value)
  guard total > 0 && !total.is_inf() else { return None }
  let mut offset = (phase % total + total) % total
  let mut start_index = 0
  while offset >= dash[start_index] {
    offset -= dash[start_index]
    start_index = (start_index + 1) % dash.length()
  }
  let contours : Array[(Array[(Double, Double)], Bool)] = []
  let mut points : Array[(Double, Double)] = []
  for segment in path {
    match segment {
      Move(x, y) => {
        if !points.is_empty() {
          contours.push((points, false))
        }
        points = [(x, y)]
      }
      Line(x, y) => points.push((x, y))
      Close => {
        contours.push((points, true))
        points = []
      }
      Cubic(_, _, _, _, _, _) => return None
    }
  }
  if !points.is_empty() {
    contours.push((points, false))
  }
  let pieces : Array[Array[(Double, Double)]] = []
  let mut steps = 0
  let mut retained = 0
  for (contour, closed) in contours {
    guard contour.length() >= 2 else { return None }
    let first = contour[0]
    if closed && contour.last() == Some(first) {
      ignore(contour.pop())
    }
    let piece_start = pieces.length()
    let mut index = start_index
    let mut remaining = dash[index] - offset
    let mut active = false
    let count = contour.length() + (if closed { 1 } else { 0 })
    for i in 1..<count {
      let b = contour[i % contour.length()]
      let mut a = contour[i - 1]
      let mut length = @math.hypot(b.0 - a.0, b.1 - a.1)
      while length > 0 {
        steps += 1
        guard steps <= 8192 else { return None }
        let step = length.min(remaining)
        let end = if step == length {
          b
        } else {
          (a.0 + (b.0 - a.0) * step / length, a.1 + (b.1 - a.1) * step / length)
        }
        if index % 2 == 0 {
          if !active {
            pieces.push([a])
            retained += 1
            active = true
          }
          pieces.last().unwrap().push(end)
          retained += 1
          guard retained <= available else { return None }
        }
        a = end
        length -= step
        remaining -= step
        if remaining <= 0 {
          index = (index + 1) % dash.length()
          remaining = dash[index]
          active = false
        }
      }
    }
    if closed && pieces.length() > piece_start + 1 {
      let head = pieces[piece_start]
      let tail = pieces.last().unwrap()
      if head[0] == first && tail.last() == Some(first) {
        for point in head[1:] {
          tail.push(point)
        }
        ignore(pieces.remove(piece_start))
      }
    }
  }
  Some(pieces)
}

///|
fn rectangle_dash_spans(
  corners : Array[(Double, Double)],
  pattern : Array[Double],
  closed : Bool,
  available : Int32,
) -> Array[(Int32, Double, Double, Double, Bool)]? {
  let dash = pattern.map(canvas_dash_value)
  guard dash.all(value => value > 0 && !value.is_inf()) else { return None }
  let shortest = dash.fold(init=dash[0], (minimum, value) => minimum.min(value))
  let lengths = Array::makei(4, edge => {
    let (x0, y0) = corners[edge]
    let (x1, y1) = corners[(edge + 1) % 4]
    (x1 - x0).abs().max((y1 - y0).abs())
  })
  // Reject dense patterns before walking them. Each edge can split one dash.
  let perimeter = lengths.fold(init=0.0, (sum, length) => sum + length)
  guard perimeter / shortest + 4 <= available.to_double() else { return None }
  let pattern_length = if dash.length() % 2 == 0 {
    dash.length()
  } else {
    dash.length() * 2
  }
  let spans : Array[(Int32, Double, Double, Double, Bool)] = []
  let mut index = 0
  let mut remaining = dash[0]
  for edge, length in lengths {
    let mut at = 0.0
    while at < length {
      let step = remaining.min(length - at)
      guard at + step > at else { return None }
      let at_end = step == length - at
      let end = if at_end { length } else { at + step }
      if index % 2 == 0 {
        let join = at_end && (if edge == 3 { closed } else { remaining > step })
        spans.push((edge, length, at, end, join))
        guard spans.length() * 2 <= available else { return None }
      }
      at = end
      remaining -= step
      if remaining == 0 {
        index = (index + 1) % pattern_length
        remaining = dash[index % dash.length()]
      }
    }
  }
  Some(spans)
}
