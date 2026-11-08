///|
fn section_spans(
  parts : Array[NumberPart],
  style : @layout.TextStyle,
  original : Array[@layout.Span]?,
  color : String?,
) -> Array[@layout.Span] {
  let spans : Array[@layout.Span] = []
  for part in parts {
    match part {
      ValueText(_) if original is Some(rich) =>
        spans.append(
          rich.map(span => {
            ..span,
            style: { ..span.style, color: color.unwrap_or(span.style.color), },
          }),
        )
      Visible(text) | ValueText(text) =>
        if !text.is_empty() {
          spans.push({ node: 0, text, style, drawing: None, field: "", })
        }
      _ => ()
    }
  }
  spans
}

///|
fn CellStyle::section_measure(
  self : CellStyle,
  section : NumberSection,
  probe : @layout.TextProbe,
  profile : Map[String, String],
  original : Array[@layout.Span]?,
  width : Double,
  repeat_fill : Bool,
) -> @layout.TextBlock raise @failure.Failure {
  let style = {
    ..self.text_style(),
    color: section.color.unwrap_or(self.color),
  }
  let blocks : Array[(NumberPart, @layout.TextBlock)] = []
  let visible : Array[NumberPart] = []
  let flush = fn() raise @failure.Failure {
    if !visible.is_empty() {
      let spans = section_spans(visible, style, original, section.color)
      if !spans.is_empty() {
        blocks.push(
          (
            Visible(""),
            probe.span_block(spans, self.size, profile, width, false, cell=true),
          ),
        )
      }
      visible.clear()
    }
  }
  for part in section.parts {
    match part {
      Skip(text) | Repeat(text) => {
        flush()
        blocks.push(
          (
            part,
            probe.text_block(text, style, profile, width, false, cell=true),
          ),
        )
      }
      _ => visible.push(part)
    }
  }
  flush()
  guard blocks.all(pair => pair.1.lines.length() == 1) else {
    @failure.reject(
      "unsupported-text", "Spaced number formats require a single text line",
    )
  }
  let natural = blocks.fold(init=0.0, (sum, pair) => {
    sum + (if pair.0 is Repeat(_) { 0 } else { pair.1.widths[0] })
  })
  let primitives : Array[@layout.PositionedPrimitive] = [
    @layout.Transform({ a: 1, b: 0, c: 0, d: 1, e: 0, f: 0, }),
  ]
  let mut x = 0.0
  let mut height = 0.0
  for (part, measured) in blocks {
    height = height.max(measured.height)
    let block = if part is Repeat(text) {
      if !repeat_fill ||
        measured.widths[0] <= 0 ||
        measured.widths[0] > width - natural {
        continue
      }
      filled_block(
        probe,
        [{ node: 0, text, style, drawing: None, field: "", }],
        self.size,
        profile,
        (width - natural).max(0.75),
        measured,
      )
    } else {
      measured
    }
    if !(part is Skip(_)) {
      primitives.push(
        @layout.Transform({ a: 1, b: 0, c: 0, d: 1, e: x, f: 0, }),
      )
      primitives.append(block.lines[0])
      primitives.push(@layout.Restore)
    }
    x += block.widths[0]
  }
  primitives.push(@layout.Restore)
  { lines: [primitives], widths: [x], height, }
}

///|
fn CellStyle::section_block(
  self : CellStyle,
  section : NumberSection,
  probe : @layout.TextProbe,
  profile : Map[String, String],
  original : Array[@layout.Span]?,
  width : Double,
  shrink : Bool,
  repeat_fill : Bool,
) -> @layout.TextBlock raise @failure.Failure {
  let mut size = self.size
  for _ in 0..<16 {
    let spans = original.map(spans => {
      spans.map(span => {
        ..span,
        style: {
          ..span.style,
          size: (span.style.size * size / self.size * 2).floor() / 2,
        },
      })
    })
    let block = { ..self, size, }.section_measure(
      section, probe, profile, spans, width, repeat_fill,
    )
    if !shrink || block.widths[0] <= width || size <= 2.5 {
      return block
    }
    let next = ((size * width / block.widths[0] * 2).floor() / 2).max(2.5)
    if next >= size {
      return block
    }
    size = next
  }
  @failure.reject(
    "limit-exceeded", "Number format shrinking exceeds 16 measurements",
  )
}
