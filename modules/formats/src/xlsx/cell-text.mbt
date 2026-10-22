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
  justify~ : Bool = self.horizontal == "justify",
  distributed~ : Bool = self.horizontal == "distributed",
  fill~ : Bool = self.horizontal == "fill",
) -> @layout.TextBlock raise @failure.Failure {
  let wrap = wrap || distributed
  let mut spans = spans.unwrap_or([
    { node: 0, text, style: self.text_style(), drawing: None, field: "", },
  ])
  if self.rotation == 255 {
    spans = stacked_spans(spans)
  }
  let mut nominal = self.size
  let mut block = probe.span_block(
    spans,
    nominal,
    profile,
    width,
    wrap,
    justify~,
    distributed~,
  )
  if fill && !wrap {
    return filled_block(probe, spans, nominal, profile, width, block)
  }
  if !shrink || wrap {
    return block
  }
  for _ in 0..<16 {
    let measured = rotated_size(block, self.rotation).0
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
    block = probe.span_block(
      spans,
      nominal,
      profile,
      width,
      false,
      justify~,
      distributed~,
    )
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
  rotation~ : Int = 0,
) -> Array[@layout.Border] raise @failure.Failure {
  if rotation != 0 && rotation != 255 {
    return place_rotated_block(
      page, block, rect, horizontal, vertical, indent, rotation,
    )
  }
  let free = (rect.height - 3 - block.height).max(0)
  let spread = vertical == "justify" || vertical == "distributed"
  let gap = if spread && block.lines.length() > 1 {
    free / (block.lines.length() - 1).to_double()
  } else {
    0.0
  }
  let top = rect.y +
    1.5 +
    (if vertical == "center" ||
      (vertical == "distributed" && block.lines.length() == 1) {
      free / 2
    } else if vertical == "bottom" {
      free
    } else {
      0.0
    })
  let offsets = block.lines.map(line => {
    guard line.get(0) is Some(@layout.Transform(matrix)) else {
      @failure.reject("invalid-drawing", "Text block requires a line transform")
    }
    matrix
  })
  let bounds : Array[@layout.Border] = []
  for index, line in block.lines {
    let y = top + index.to_double() * gap
    let x = rect.x +
      2.25 +
      (if ["left", "distributed"].contains(horizontal) { indent } else { 0.0 }) +
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
          @layout.Transform({ a: 1, b: 0, c: 0, d: 1, e: x, f: y, }),
          ..line,
          @layout.Restore,
        ],
        rect,
      ),
    )
    let rect = grid_intersection(
      {
        x: x + offsets[index].e,
        y: y + offsets[index].f,
        width: block.widths[index],
        height: offsets
        .get(index + 1)
        .map(matrix => matrix.f)
        .unwrap_or(block.height) -
        offsets[index].f,
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
  } else if self.horizontal != "general" &&
    !(self.horizontal == "fill" && self.wrap) {
    self.horizontal
  } else if self.rotation == 255 {
    "center"
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
