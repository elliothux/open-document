///|
fn form_smooth_closed(path : Array[@layout.PathSegment]) -> Bool {
  guard path is [Move(x, y), ..] && path.last() is Some(Close) else {
    return false
  }
  fn smooth(a : (Double, Double), b : (Double, Double)) -> Bool {
    let length = (a.0 * a.0 + a.1 * a.1).sqrt() * (b.0 * b.0 + b.1 * b.1).sqrt()
    length > 0 &&
    a.0 * b.0 + a.1 * b.1 > 0 &&
    (a.0 * b.1 - a.1 * b.0).abs() <= length * 0.000000001
  }
  let start = (x, y)
  let mut point = start
  let mut first : (Double, Double)? = None
  let mut prior : (Double, Double)? = None
  for segment in path[1:path.length() - 1] {
    match segment {
      Cubic(a, b, c, d, x, y) => {
        let tangent = (a - point.0, b - point.1)
        if prior is Some(prior) && !smooth(prior, tangent) {
          return false
        }
        if first is None {
          first = Some(tangent)
        }
        prior = Some((x - c, y - d))
        point = (x, y)
      }
      _ => return false
    }
  }
  point == start &&
  first is Some(first) &&
  prior is Some(prior) &&
  smooth(prior, first)
}

///|
fn form_hull_inside(
  path : Array[@layout.PathSegment],
  matrix : @layout.Matrix,
  box : @layout.Border,
  radius : Double,
) -> Bool raise {
  let dx = radius * (matrix.a * matrix.a + matrix.c * matrix.c).sqrt()
  let dy = radius * (matrix.b * matrix.b + matrix.d * matrix.d).sqrt()
  fn inside(x : Double, y : Double) -> Bool {
    let (x, y) = matrix.point(x, y)
    x - dx >= box.x - 0.0000001 &&
    x + dx <= box.x + box.width + 0.0000001 &&
    y - dy >= box.y - 0.0000001 &&
    y + dy <= box.y + box.height + 0.0000001
  }
  guard !path.is_empty() else { return false }
  for segment in path {
    @pdfcore.sdk_check(1)
    match segment {
      Move(x, y) | Line(x, y) => if !inside(x, y) { return false }
      Cubic(a, b, c, d, x, y) =>
        if !inside(a, b) || !inside(c, d) || !inside(x, y) {
          return false
        }
      Close => ()
    }
  }
  true
}

///|
// A contained Form needs no second antialiased boundary over its already bounded paint.
fn form_clip_redundant(
  commands : Array[@layout.DrawCommand],
  box : @layout.Border,
  matrix : @layout.Matrix,
) -> Bool raise {
  guard commands.length() >= 2 &&
    commands[0] is ClipPath(_, _) &&
    commands.last() is Some(Restore) else {
    return false
  }
  let inverse = matrix.inverse()
  let mut transform = @layout.Matrix::identity()
  let mut style = @layout.DrawStyle::default()
  let mut contained = false
  let stack : Array[(@layout.Matrix, @layout.DrawStyle, Bool)] = []
  for command in commands[1:commands.length() - 1] {
    @pdfcore.sdk_check(1)
    match command {
      Style(value) => style = value
      Transform(value) => {
        stack.push((transform, style, contained))
        transform = transform.then(value)
      }
      ClipPath(path, _) => {
        stack.push((transform, style, contained))
        contained = contained ||
          form_hull_inside(path, inverse.then(transform), box, 0)
      }
      Restore => {
        guard stack.pop() is Some((matrix, prior, safe)) else { return false }
        transform = matrix
        style = prior
        contained = safe
      }
      Path(path, _, stroke, width)
      | OutlinedPath(path, _, stroke, width, _)
      | FilledOutline(path, _, stroke, width, _)
      | RectangleDashedPath(path, _, stroke, width, _)
      | DashedPath(path, _, stroke, width, _) if !contained => {
        if !stroke.is_empty() && width == 0 {
          return false
        }
        let radius = if stroke.is_empty() {
          0.0
        } else {
          @pdfcore.sdk_check(path.length())
          let factor = if style.join == 0 && !form_smooth_closed(path) {
            style.miter
          } else {
            1.0
          }
          let factor = factor.max(if style.cap == 2 { 2.0.sqrt() } else { 1.0 })
          width / 2.0 * factor
        }
        if !form_hull_inside(path, inverse.then(transform), box, radius) {
          return false
        }
      }
      _ => if !contained { return false }
    }
  }
  stack.is_empty()
}

///|
fn page_bounds_in(
  page : SourcePage,
  matrix : @layout.Matrix,
) -> (Double, Double, Double, Double) raise @failure.Failure {
  let inverse = matrix.inverse()
  let corners = [
    (0.0, 0.0),
    (page.width, 0.0),
    (0.0, page.height),
    (page.width, page.height),
  ].map(p => checked_point(inverse, p.0, p.1))
  (
    corners.fold(init=corners[0].0, (a, p) => a.min(p.0)),
    corners.fold(init=corners[0].1, (a, p) => a.min(p.1)),
    corners.fold(init=corners[0].0, (a, p) => a.max(p.0)),
    corners.fold(init=corners[0].1, (a, p) => a.max(p.1)),
  )
}

///|
fn visible_form_bbox(
  page : SourcePage,
  value : @syntax.PdfObject,
  matrix : @layout.Matrix,
) -> (Double, Double, Double, Double)? raise @failure.Failure {
  let (x, y, r, b) = rectangle(value, limit=2147483648.0)
  if [x, y, r, b].all(v => v.abs() <= 1000000000) {
    return Some((x, y, r, b))
  }
  let (left, top, right, bottom) = page_bounds_in(page, matrix)
  // The enclosing page clip already bounds this part of the form.
  let (x, y, r, b) = (
    x.max(left - 1),
    y.max(top - 1),
    r.min(right + 1),
    b.min(bottom + 1),
  )
  if x < r && y < b {
    Some((x, y, r, b))
  } else {
    None
  }
}
