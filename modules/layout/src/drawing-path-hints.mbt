///|
fn four_line_corners(
  path : ArrayView[PathSegment],
) -> (
  (Double, Double),
  (Double, Double),
  (Double, Double),
  (Double, Double),
  PathSegment,
)? {
  guard path is [Move(x0, y0), Line(x1, y1), Line(x2, y2), Line(x3, y3), end] else {
    return None
  }
  Some(((x0, y0), (x1, y1), (x2, y2), (x3, y3), end))
}

///|
fn rectangular_diagonal(
  path : ArrayView[PathSegment],
) -> ((Double, Double), (Double, Double))? {
  guard four_line_corners(path) is Some((a, b, c, d, end)) &&
    (end is Close || (end is Line(x, y) && (x, y) == a)) else {
    return None
  }
  let axis_edge = (start : (Double, Double), end : (Double, Double)) => {
    let (x, y) = start
    let (next_x, next_y) = end
    (x == next_x) != (y == next_y)
  }
  if axis_edge(a, b) && axis_edge(b, c) && axis_edge(c, d) && axis_edge(d, a) {
    Some((a, c))
  } else {
    None
  }
}

///|
fn clip_rectangle(
  path : ArrayView[PathSegment],
) -> (Double, Double, Double, Double)? {
  guard rectangular_diagonal(path) is Some(((x0, y0), (x1, y1))) &&
    x0 != x1 &&
    y0 != y1 else {
    return None
  }
  Some((x0.min(x1), y0.min(y1), x0.max(x1), y0.max(y1)))
}

///|
fn linear_bounds(
  path : Array[PathSegment],
) -> (Double, Double, Double, Double)? {
  guard path.get(0) is Some(Move(x, y)) else { return None }
  let mut left = x
  let mut top = y
  let mut right = x
  let mut bottom = y
  for segment in path {
    match segment {
      Move(x, y) | Line(x, y) => {
        left = left.min(x)
        top = top.min(y)
        right = right.max(x)
        bottom = bottom.max(y)
      }
      Close => ()
      Cubic(_, _, _, _, _, _) => return None
    }
  }
  Some((left, top, right, bottom))
}

///|
fn stroke_geometry(path : Array[PathSegment]) -> (String?, Bool) {
  let length = path.length()
  if length > 0 && length % 5 == 0 {
    let rectangles = for i = 0; i < length; i = i + 5 {
      if (length > 5 && !(path[i + 4] is Close)) ||
        rectangular_diagonal(path[i:i + 5]) is None {
        break false
      }
    } nobreak {
      true
    }
    if rectangles {
      let kind = if path[4] is Close { "rectangles" } else { "openRectangle" }
      return (Some(kind), false)
    }
  }
  let mut pairs = length > 0 && length % 2 == 0
  let mut closed = false
  // Canvas flattening preserves the source commands for canonical linear subpaths.
  let mut canonical = length >= 5
  let mut active = false
  let mut start = (0.0, 0.0)
  for i, segment in path {
    match segment {
      Move(x, y) => {
        pairs = pairs && i % 2 == 0
        active = true
        start = (x, y)
      }
      Line(x, y) => {
        pairs = pairs && i % 2 == 1
        canonical = canonical && active
        closed = closed || (x, y) == start
      }
      Close => {
        pairs = false
        closed = true
        canonical = canonical && active
        active = false
      }
      Cubic(_, _, _, _, _, _) => return (Some("curve"), false)
    }
  }
  if closed {
    (Some("closed"), canonical)
  } else if pairs {
    (Some("segments"), false)
  } else {
    (None, canonical)
  }
}

///|
/// Prepare bounded straight strokes in source coordinates before device sampling.
pub fn DrawCommand::linear_path(
  path : Array[PathSegment],
  fill : String,
  stroke : String,
  width : Double,
  style : DrawStyle,
  available : Int32,
) -> DrawCommand {
  let original : DrawCommand = Path(path, fill, stroke, width)
  let solid = style.cap == 0 &&
    style.join == 0 &&
    style.dash.is_empty() &&
    (fill.is_empty() || (style.strokeAlpha == 1 && style.blend == Normal))
  let round_dash = style.cap == 1 &&
    style.join == 1 &&
    !style.dash.is_empty() &&
    fill.is_empty()
  let rectangle_dash = style.cap == 0 &&
    style.join == 0 &&
    canvas_dash_value(style.dashOffset) == 0 &&
    !style.dash.is_empty() &&
    path.length() == 5
  guard available >= 5 &&
    !stroke.is_empty() &&
    width > 0 &&
    (solid || round_dash || rectangle_dash) &&
    path.length() <= 256 &&
    path.get(0) is Some(Move(_, _)) else {
    return original
  }
  let mut open = false
  for segment in path {
    match segment {
      Move(x, y) if x.abs() <= 1000000000 && y.abs() <= 1000000000 =>
        open = true
      Close if open => open = false
      Line(x, y) if open && x.abs() <= 1000000000 && y.abs() <= 1000000000 => ()
      _ => return original
    }
  }
  if round_dash {
    return match straight_dash_pieces(path, style, available) {
      Some(pieces) => DashedPath(path, fill, stroke, width, pieces)
      None => original
    }
  }
  let (geometry, _) = stroke_geometry(path)
  if rectangle_dash {
    guard geometry is Some("rectangles" | "openRectangle") &&
      four_line_corners(path[:]) is Some((a, b, c, d, end)) &&
      rectangle_dash_spans([a, b, c, d], style.dash, end is Close, available)
      is Some(spans) else {
      return original
    }
    return RectangleDashedPath(path, fill, stroke, width, spans)
  }
  // Compact segments and rectangles keep their specialized pixel alignment.
  guard !(geometry is Some("segments" | "rectangles" | "openRectangle")) &&
    (!fill.is_empty() || geometry != Some("closed")) else {
    return original
  }
  let outline = stroke_contour_impl(
    path,
    width,
    "flat",
    "miter",
    style.miter,
    true,
  ) catch {
    _ => return original
  }
  if outline.is_empty() || outline.length() > available {
    original
  } else {
    OutlinedPath(path, fill, stroke, width, outline)
  }
}

///|
/// Prepare a fill outline while retaining the source path for native extraction.
pub fn DrawCommand::prepare_fill_outline(
  self : DrawCommand,
  style : DrawStyle,
) -> DrawCommand {
  let (path, fill, stroke, width) = match self {
    Path(path, fill, stroke, width)
    | OutlinedPath(path, fill, stroke, width, _) => (path, fill, stroke, width)
    _ => return self
  }
  if width > 0 &&
    !fill.is_empty() &&
    (fill == stroke || fill.to_lower() == stroke.to_lower()) &&
    style.fillAlpha == 1 &&
    style.strokeAlpha == 1 &&
    style.blend == Normal &&
    style.join == 0 &&
    style.dash.is_empty() &&
    diamond_outline(path, width) is Some((miter, outline)) &&
    // Chromium exposes the stroke miter as a single-precision value.
    miter <= Float::from_double(style.miter).to_double() {
    FilledOutline(path, fill, stroke, width, outline)
  } else {
    self
  }
}

///|
fn diamond_outline(
  path : Array[PathSegment],
  width : Double,
) -> (Double, Array[PathSegment])? {
  guard four_line_corners(path[:]) is Some((a, b, c, d, Close)) else {
    return None
  }
  let points = [a, b, c, d]
  let (x0, y0) = a
  let mut left = x0
  let mut right = x0
  let mut top = y0
  let mut bottom = y0
  for point in points {
    let (x, y) = point
    left = left.min(x)
    right = right.max(x)
    top = top.min(y)
    bottom = bottom.max(y)
  }
  let cx = (left + right) / 2
  let cy = (top + bottom) / 2
  let rx = (right - left) / 2
  let ry = (bottom - top) / 2
  guard rx > 0 && ry > 0 else { return None }
  for i in 0..<4 {
    let (x, y) = points[i]
    let (next_x, next_y) = points[(i + 1) % 4]
    guard x != next_x &&
      y != next_y &&
      (
        (x == cx && (y == top || y == bottom)) ||
        (y == cy && (x == left || x == right))
      ) else {
      return None
    }
  }
  let scale = rx.max(ry)
  let (nx, ny) = (rx / scale, ry / scale)
  let diagonal = (nx * nx + ny * ny).sqrt() * scale
  let dx = width * diagonal / (2 * ry)
  let dy = width * diagonal / (2 * rx)
  let miter = diagonal / rx.min(ry)
  guard !dx.is_inf() &&
    !dx.is_nan() &&
    !dy.is_inf() &&
    !dy.is_nan() &&
    !miter.is_inf() &&
    !miter.is_nan() else {
    return None
  }
  let outline : Array[PathSegment] = []
  for i, point in points {
    let (x, y) = point
    let px = if x == cx { cx } else if x == left { x - dx } else { x + dx }
    let py = if y == cy { cy } else if y == top { y - dy } else { y + dy }
    outline.push(if i == 0 { Move(px, py) } else { Line(px, py) })
  }
  outline.push(Close)
  Some((miter, outline))
}
