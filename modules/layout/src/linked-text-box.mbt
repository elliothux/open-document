///|
fn DrawingFrame::prepare_linked_text(
  self : DrawingFrame,
  probe : TextProbe,
  profile : Map[String, String],
) -> DrawingFrame raise @failure.Failure {
  guard self.content is TextBox(shape, text) else { return self }
  let area = self.text_box_rect(shape, text)
  guard text.flowFrames.last() == Some((area.width, area.height)) else {
    @failure.reject(
      "invalid-drawing", "Linked text area differs from its frame",
    )
  }
  let mut paragraph_index = 0
  let mut offset = 0
  let mut visible : Array[Line] = []
  for (width, height) in text.flowFrames {
    visible = []
    if paragraph_index == text.paragraphs.length() {
      continue
    }
    let original = text.paragraphs[paragraph_index]
    let spans : Array[Span] = []
    let mut consumed = 0
    let mut first_skip = 0
    for span in original.spans {
      let end = consumed + span.text.length()
      if end > offset ||
        (end == offset && span.text.is_empty() && spans.is_empty()) {
        let skip = (offset - consumed).max(0)
        if spans.is_empty() {
          first_skip = skip
        }
        spans.push({ ..span, text: span.text[skip:].to_owned(), })
      }
      consumed = end
    }
    let remaining = [
      {
        ..original,
        spans,
        first: if offset > 0 {
          0
        } else {
          original.first
        },
        before: if offset > 0 {
          0
        } else {
          original.before
        },
      },
    ]
    remaining.append(text.paragraphs[paragraph_index + 1:])
    let frame : DrawingFrame = {
      width,
      height,
      anchor: None,
      effectExtent: (0, 0, 0, 0),
      content: TextBox({ ..shape, preset: "rect", }, {
        ..text,
        paragraphs: remaining,
        insets: [0, 0, 0, 0],
        flowFrames: [],
      }),
    }
    guard frame.prepare_text(probe, profile).content is TextBox(_, prepared) else {
      abort("Text box expected")
    }
    let first_length = spans.get(0).map(s => s.text.length()).unwrap_or(0)
    for line in prepared.lines {
      if line.y + line.height > height + 0.000001 {
        break
      }
      let shift = if line.paragraph == original.id { offset } else { 0 }
      visible.push({
        ..line,
        start: line.start + shift,
        end: line.end + shift,
        carets: line.carets.map(c => { ..c, offset: c.offset + shift, }),
        runs: line.runs.map(run => {
          ..run,
          start: run.start + shift,
          sources: run.sources.map(source => {
            let prefix = if shift > 0 &&
              run.start + source.offset < first_length {
              first_skip
            } else {
              0
            }
            {
              ..source,
              start: source.start + prefix,
              end: source.end + prefix,
            }
          }),
        }),
      })
    }
    if visible.last() is Some(last) {
      while text.paragraphs[paragraph_index].id != last.paragraph {
        paragraph_index += 1
      }
      offset = last.end
      let length = text.paragraphs[paragraph_index].spans.fold(init=0, (
        sum,
        span,
      ) => sum + span.text.length())
      if offset == length {
        paragraph_index += 1
        offset = 0
      }
    }
  }
  {
    ..self,
    content: TextBox(shape, {
      ..text,
      lines: visible.map(line => {
        ..line,
        x: line.x + area.x,
        y: line.y + area.y,
        areaX: line.areaX + area.x,
        bars: line.bars.map(x => x + area.x),
        carets: line.carets.map(c => {
          ..c,
          before: c.before + area.x,
          after: c.after + area.x,
        }),
        runs: line.runs.map(run => {
          ..run,
          x: run.x + area.x,
          baseline: run.baseline + area.y,
        }),
      }),
    }),
  }
}
