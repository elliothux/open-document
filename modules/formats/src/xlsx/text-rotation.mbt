///|
fn rotation_components(rotation : Int32) -> (Double, Double) {
  let degrees = if rotation <= 90 { rotation } else { 90 - rotation }
  if rotation == 0 || rotation == 255 {
    (1, 0)
  } else if degrees == 90 {
    (0, 1)
  } else if degrees == -90 {
    (0, -1)
  } else {
    let angle = degrees.to_double() * @math.PI / 180
    (@math.cos(angle), @math.sin(angle))
  }
}

///|
fn rotated_size(
  block : @layout.TextBlock,
  rotation : Int32,
) -> (Double, Double) {
  let (cos, sin) = rotation_components(rotation)
  let width = block.widths.fold(init=0.0, (a, b) => a.max(b))
  (
    width * cos + block.height * sin.abs(),
    block.height * cos + width * sin.abs(),
  )
}

///|
fn stacked_spans(spans : Array[@layout.Span]) -> Array[@layout.Span] {
  let text = spans.map(span => span.text).join("")
  let boundaries = Map(
    @layout.grapheme_boundaries(text).map(offset => (offset, true)),
  )
  let mut offset = 0
  let mut previous_break = true
  spans.map(span => {
    let output = StringBuilder()
    for ch in span.text {
      let line_break = ch == '\n' || ch == '\r'
      if boundaries.contains(offset) && !previous_break && !line_break {
        output.write_string("\n")
      }
      output.write_char(ch)
      previous_break = line_break
      offset += ch.to_string().length()
    }
    { ..span, text: output.to_string(), }
  })
}

///|
fn place_rotated_block(
  page : PagePaint,
  block : @layout.TextBlock,
  rect : @layout.Border,
  horizontal : String,
  vertical : String,
  indent : Double,
  rotation : Int32,
) -> Array[@layout.Border] {
  let (cos, sin) = rotation_components(rotation)
  let (width, height) = rotated_size(block, rotation)
  let x = rect.x +
    2.25 +
    (if horizontal == "right" {
      (rect.width - 4.5 - indent - width).max(0)
    } else if horizontal == "center" {
      (rect.width - 4.5 - width).max(0) / 2
    } else {
      indent
    })
  let free = (rect.height - 3 - height).max(0)
  let y = rect.y +
    1.5 +
    (if vertical == "bottom" {
      free
    } else if ["center", "justify", "distributed"].contains(vertical) {
      free / 2
    } else {
      0.0
    })
  let natural = block.widths.fold(init=0.0, (a, b) => a.max(b))
  let matrix : @layout.Matrix = {
    a: cos,
    b: -sin,
    c: sin,
    d: cos,
    e: x - (sin * block.height).min(0),
    f: y - (-sin * natural).min(0),
  }
  for index, line in block.lines {
    let dx = if horizontal == "right" {
      natural - block.widths[index]
    } else if horizontal == "center" {
      (natural - block.widths[index]) / 2
    } else {
      0.0
    }
    page.texts.push(
      (
        [
          @layout.Transform(matrix),
          @layout.Transform({ a: 1, b: 0, c: 0, d: 1, e: dx, f: 0, }),
          ..line,
          @layout.Restore,
          @layout.Restore,
        ],
        rect,
      ),
    )
  }
  let bounds = grid_intersection({ x, y, width, height, }, rect)
  if bounds.width > 0 && bounds.height > 0 {
    [bounds]
  } else {
    []
  }
}
