///|
priv struct MeasuredSpan {
  span : Span
  start : Int
  end : Int
  font : Int
}

///|
fn measure_line(
  probe : TextProbe,
  spans : Array[MeasuredSpan],
  start : Int,
  end : Int,
) -> (Double, Array[PlacedRun], Array[PlacedImage]) raise @failure.Failure {
  let runs : Array[PlacedRun] = []
  let images : Array[PlacedImage] = []
  let text = StringBuilder()
  for item in spans {
    let a = start.max(item.start)
    let b = end.min(item.end)
    if a < b {
      text.write_string(
        item.span.text[a - item.start:b - item.start].to_owned(),
      )
    }
  }
  let text = text.to_string()
  let bidi = @bidi.process(text)
  let groups : Array[LineGroup] = []
  let char_groups : Array[Int] = []
  let mut offset = 0
  let mut span_index = 0
  for i, ch in bidi.chars {
    while span_index < spans.length() && spans[span_index].end <= start + offset {
      span_index += 1
    }
    guard span_index < spans.length() else {
      @failure.reject("layout-failed", "Missing source span")
    }
    let item = spans[span_index]
    let next = offset + (if ch.to_int() > 0xffff { 2 } else { 1 })
    if groups.last() is Some(group) &&
      group.image is None &&
      item.span.image is None &&
      group.font == item.font &&
      group.style.size == item.span.style.size &&
      group.style.color == item.span.style.color &&
      group.level == bidi.levels[i] {
      groups[groups.length() - 1] = { ..group, end: next, }
    } else {
      groups.push({
        start: offset,
        end: next,
        font: item.font,
        style: item.span.style,
        level: bidi.levels[i],
        image: item.span.image,
      })
    }
    char_groups.push(groups.length() - 1)
    offset = next
  }
  let visual : Array[Int] = []
  for i in @bidi.reorder(bidi) {
    if visual.last() != Some(char_groups[i]) {
      visual.push(char_groups[i])
    }
  }
  let mut width = 0.0
  for index in visual {
    let group = groups[index]
    if group.image is Some(image) {
      images.push({
        key: image.key,
        x: width,
        y: 0,
        width: image.width,
        height: image.height,
      })
      width += image.width
      continue
    }
    let fragment = text[group.start:group.end].to_owned()
    let batch = probe.shape(
      fragment,
      group.style.size,
      "und",
      primary=group.font,
      base=group.level,
    )
    guard batch.diagnostics.is_empty() else {
      @failure.reject(
        "missing-glyph", "Preview requires every glyph; unsupported or missing glyph in paragraph",
      )
    }
    let sources : Array[SourceRange] = []
    for item in spans {
      let a = (start + group.start).max(item.start)
      let b = (start + group.end).min(item.end)
      if a < b {
        sources.push({
          node: item.span.node,
          start: a - item.start,
          end: b - item.start,
          offset: a - start - group.start,
        })
      }
    }
    runs.push({
      sources,
      color: group.style.color,
      text: fragment,
      glyphs: batch.glyphs,
      bidi: batch.runs.map(run => { ..run, level: group.level, }),
      x: width,
      baseline: 0,
    })
    width += batch.width
  }
  (width, runs, images)
}

///|
priv struct LineGroup {
  start : Int
  end : Int
  font : Int
  style : TextStyle
  level : Int
  image : InlineImage?
}

///|
fn paragraph_lines(
  probe : TextProbe,
  paragraph : Paragraph,
  profile : Map[String, String],
  available : Double,
) -> Array[Line] raise @failure.Failure {
  let spans : Array[MeasuredSpan] = []
  let text = StringBuilder()
  let mut length = 0
  let mut size = 0.0
  let mut ascent = 0.0
  let mut descent = 0.0
  for span in paragraph.spans {
    guard span.style.size > 0 && span.style.size <= 1024 else {
      @failure.reject("invalid-style", "Invalid font size")
    }
    let font = if span.image is Some(_) {
      -1
    } else {
      guard profile.get(span.style.font) is Some(identity) else {
        @failure.reject(
          "missing-font",
          "Missing font profile mapping: " + span.style.font,
        )
      }
      probe.font_index(identity)
    }
    spans.push({ span, start: length, end: length + span.text.length(), font, })
    if font >= 0 {
      let (a, d) = probe.line_metrics(font, span.style.size)
      ascent = ascent.max(a)
      descent = descent.max(d)
    }
    text.write_string(span.text)
    length += span.text.length()
    size = size.max(span.style.size)
  }
  guard length <= 4096 else {
    @failure.reject("limit-exceeded", "Paragraph exceeds 4096 UTF-16 units")
  }
  let text = text.to_string()
  let size = if size > 0 { size } else { 11 }
  let line_height = if paragraph.exact {
    paragraph.line
  } else {
    ((ascent + descent).max(size) * paragraph.line).max(paragraph.minimum)
  }
  guard line_height > 0 &&
    paragraph.minimum >= 0 &&
    paragraph.left >= 0 &&
    paragraph.right >= 0 &&
    available - paragraph.left - paragraph.right - paragraph.first.max(0) > 0 else {
    @failure.reject("invalid-style", "Paragraph has no usable line area")
  }
  let lines : Array[Line] = []
  let breaks = @linebreak.linebreaks(text)
  let graphemes = @linebreak.grapheme_indices_uax29(text)
  let mut start = 0
  // shortcut: full-prefix shaping is bounded to 4096 units; optimize for long unbroken text when required.
  while start < text.length() || lines.is_empty() {
    let indent = paragraph.left + (if start == 0 { paragraph.first } else { 0 })
    let limit = available - indent - paragraph.right
    let mut end = start
    let mut forced = false
    for (boundary, kind) in breaks {
      if boundary <= start {
        continue
      }
      let mut visible_end = boundary
      if boundary > start &&
        (text[boundary - 1] == 10 || text[boundary - 1] == 12) {
        visible_end -= 1
      }
      let (width, _, _) = measure_line(probe, spans, start, visible_end)
      if width > limit {
        break
      }
      end = boundary
      if kind is @linebreak.Mandatory {
        forced = true
        break
      }
    }
    if end == start && start < text.length() {
      // shortcut: emergency wrap uses grapheme boundaries, upgrade when hyphenation is supported.
      for (a, b) in graphemes {
        if a < start {
          continue
        }
        let (width, _, _) = measure_line(probe, spans, start, b)
        if width > limit && end > start {
          break
        }
        end = b
        if width > limit {
          break
        }
      }
    }
    let page_break = end > start && text[end - 1] == 12
    let visible_end = if forced &&
      end > start &&
      (text[end - 1] == 10 || page_break) {
      end - 1
    } else {
      end
    }
    let (width, runs, images) = measure_line(probe, spans, start, visible_end)
    guard width <= limit else {
      @failure.reject(
        "layout-overflow", "A grapheme or inline image exceeds line width",
      )
    }
    let mut line_ascent = 0.0
    let mut line_descent = 0.0
    for run in runs {
      for glyph in run.glyphs {
        let (a, d) = probe.line_metrics(
          glyph.font,
          glyph.scale * probe.fonts[glyph.font].upem.to_double(),
        )
        line_ascent = line_ascent.max(a)
        line_descent = line_descent.max(d)
      }
    }
    if line_ascent + line_descent == 0 && images.is_empty() {
      line_ascent = if ascent > 0 { ascent } else { size * 0.8 }
      line_descent = if descent > 0 { descent } else { size * 0.2 }
    }
    let line_height = if paragraph.exact {
      paragraph.line
    } else {
      ((line_ascent + line_descent) * paragraph.line).max(paragraph.minimum)
    }
    let height = images
      .iter()
      .fold(init=line_height, (height, image) => {
        height.max(image.height + line_descent)
      })
    let baseline = if images.is_empty() {
      line_ascent
    } else {
      height - line_descent
    }
    let alignment = match paragraph.align {
      "center" => (limit - width).max(0) / 2
      "right" => (limit - width).max(0)
      _ => 0.0
    }
    lines.push({
      paragraph: paragraph.id,
      text: text[start:visible_end].to_owned(),
      start,
      end,
      x: indent + alignment,
      y: if page_break {
        -1
      } else {
        0
      },
      width,
      height,
      runs: runs.map(run => { ..run, baseline, }),
      images: images.map(image => { ..image, y: baseline - image.height, }),
    })
    guard end > start || start == text.length() else {
      @failure.reject("layout-failed", "Line breaker made no progress")
    }
    start = end
  }
  if text.has_suffix("\n") {
    lines.push({
      paragraph: paragraph.id,
      text: "",
      start,
      end: start,
      x: paragraph.left,
      y: 0,
      width: 0,
      height: line_height.max(size),
      runs: [],
      images: [],
    })
  }
  lines
}

///|
