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
  number~ : NumberSection? = None,
  repeat_fill~ : Bool = true,
) -> @layout.TextBlock raise @failure.Failure {
  if number is Some(section) {
    if section.parts.any(part => part is Skip(_) || part is Repeat(_)) {
      // shortcut: Spaced numeric sections use one unrotated line; extend for source cells that require wrapping or rotation.
      guard !wrap && !justify && !distributed && !fill && self.rotation == 0 else {
        @failure.reject(
          "unsupported-text", "Spaced number format layout requires an unrotated single line",
        )
      }
      return self.section_block(
        section, probe, profile, spans, width, shrink, repeat_fill,
      )
    }
    let style = {
      ..self.text_style(),
      color: section.color.unwrap_or(self.color),
    }
    return self.cell_text_block(
      probe,
      profile,
      text,
      Some(section_spans(section.parts, style, spans, section.color)),
      width,
      wrap~,
      shrink~,
      justify~,
      distributed~,
      fill~,
    )
  }
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
    cell=true,
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
      cell=true,
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
  rotation~ : Int32 = 0,
  cell~ : Bool = false,
  mirror~ : Double? = None,
) -> Array[@layout.Border] raise @failure.Failure {
  if rotation != 0 && rotation != 255 {
    return place_rotated_block(
      page, block, rect, horizontal, vertical, indent, rotation,
    )
  }
  let free = (rect.height - (if cell { 0 } else { 3 }) - block.height).max(0)
  let spread = vertical == "justify" || vertical == "distributed"
  let gap = if spread && block.lines.length() > 1 {
    free / (block.lines.length() - 1).to_double()
  } else {
    0.0
  }
  let top = rect.y +
    (if cell { 0.75 } else { 1.5 }) +
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
    let x = if cell && horizontal == "center" {
      // Native cell centers include the grid pixel and round the origin at 96 dpi.
      let logical = mirror
        .map(width => width - rect.x - rect.width)
        .unwrap_or(rect.x)
      let x = ((logical + (rect.width - block.widths[index]) / 2 + 0.75) / 0.75).round() *
        0.75
      mirror.map(width => width - x - block.widths[index]).unwrap_or(x)
    } else {
      rect.x +
      2.25 +
      (if ["left", "distributed"].contains(horizontal) { indent } else { 0.0 }) +
      (if horizontal == "right" {
        // The right grid edge contributes one pixel to the cell's usable width.
        rect.width -
        (if cell { 3.75 } else { 4.5 }) -
        indent -
        block.widths[index]
      } else if horizontal == "center" {
        (rect.width - 4.5 - block.widths[index]) / 2
      } else {
        0.0
      }).max(0)
    }
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
  guard @layout.font_profile_identity(profile, self.normal_font)
    is Some(identity) else {
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
