///|
fn CellStyle::cell_text_block(
  self : CellStyle,
  probe : @layout.TextProbe,
  profile : Map[String, String],
  text : String,
  spans : Array[@layout.Span]?,
  width : Double,
  wrap~ : Bool = self.wrap,
  shrink~ : Bool = self.shrink,
) -> @layout.TextBlock raise @failure.Failure {
  let mut spans = spans.unwrap_or([
    { node: 0, text, style: self.text_style(), drawing: None, field: "", },
  ])
  let mut nominal = self.size
  let mut block = probe.span_block(spans, nominal, profile, width, wrap)
  if !shrink || wrap {
    return block
  }
  for _ in 0..<16 {
    let measured = block.widths.fold(init=0.0, (a, b) => a.max(b))
    if measured <= width {
      return block
    }
    let ratio = width / measured
    // ONLYOFFICE reduces each run in half-point steps to a 2.5pt floor; source sizes stay intact.
    let reduced = fn(size : Double) {
      ((size * ratio * 2).floor() / 2).max(2.5).min(size)
    }
    let mut changed = false
    let next = spans.map(span => {
      let size = reduced(span.style.size)
      changed = changed || size != span.style.size
      { ..span, style: { ..span.style, size, }, }
    })
    if !changed {
      return block
    }
    spans = next
    nominal = reduced(nominal)
    block = probe.span_block(spans, nominal, profile, width, false)
  }
  @failure.reject(
    "limit-exceeded", "Cell text shrinking exceeds 16 measurements",
  )
}

///|
fn place_block(
  page : PagePaint,
  block : @layout.TextBlock,
  rect : @layout.Border,
  horizontal : String,
  vertical : String,
  indent : Double,
) -> Array[@layout.Border] raise @failure.Failure {
  let top = rect.y +
    1.5 +
    (if vertical == "top" {
      0.0
    } else if vertical == "center" {
      (rect.height - 3 - block.height) / 2
    } else {
      rect.height - 3 - block.height
    }).max(0)
  let offsets = block.lines.map(line => {
    guard line.get(0) is Some(@layout.Transform(matrix)) else {
      @failure.reject("invalid-drawing", "Text block requires a line transform")
    }
    matrix.f
  })
  let bounds : Array[@layout.Border] = []
  for index, line in block.lines {
    let x = rect.x +
      2.25 +
      (if horizontal == "left" { indent } else { 0.0 }) +
      (if horizontal == "right" {
        rect.width - 4.5 - indent - block.widths[index]
      } else if horizontal == "center" {
        (rect.width - 4.5 - block.widths[index]) / 2
      } else {
        0.0
      }).max(0)
    page.texts.push(
      (
        [
          @layout.Transform({ a: 1, b: 0, c: 0, d: 1, e: x, f: top, }),
          ..line,
          @layout.Restore,
        ],
        rect,
      ),
    )
    let rect = grid_intersection(
      {
        x,
        y: top + offsets[index],
        width: block.widths[index],
        height: offsets.get(index + 1).unwrap_or(block.height) - offsets[index],
      },
      rect,
    )
    if rect.width > 0 && rect.height > 0 {
      bounds.push(rect)
    }
  }
  bounds
}

///|
fn CellStyle::text_alignment(
  self : CellStyle,
  value : Value,
  formulas : Bool,
) -> String {
  if formulas && (self.horizontal == "general" || value is Number(_)) {
    "left"
  } else if self.horizontal != "general" {
    self.horizontal
  } else {
    match value {
      Number(_) => "right"
      Boolean(_) | Error(_) => "center"
      _ => "left"
    }
  }
}

///|
fn Session::indent_unit(
  self : Session,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Double raise @failure.Failure {
  guard profile.get(self.normal_font) is Some(identity) else {
    @failure.reject(
      "missing-font",
      "Missing font profile mapping: " + self.normal_font,
    )
  }
  let space = probe.shape(
    " ",
    self.normal_size,
    "en",
    primary=probe.font_index(identity),
  )
  // Native cell indentation uses three rounded Normal-font spaces, independent of the cell font.
  (space.width / 0.75).round() * 0.75 * 3
}
