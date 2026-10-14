///|
priv struct MeasuredSpan {
  span : Span
  start : Int
  end : Int
  font : Int
}

///|
fn LineSpacing::metrics(
  self : LineSpacing,
  ascent : Double,
  descent : Double,
) -> (Double, Double, Bool) {
  match self {
    Auto(_) => (ascent + descent, ascent, false)
    AtLeast(value) => ((ascent + descent).max(value / 20), ascent, false)
    // Match the fixed LibreOffice profile: exact lines place the baseline at 4/5 height.
    Exact(value) => (value / 20, value / 25, true)
  }
}

///|
fn measure_line(
  probe : TextProbe,
  spans : Array[MeasuredSpan],
  paragraph : @bidi.BidiParagraph,
  start : Int,
  end : Int,
  boundaries : Array[Int],
  spaces : Map[Int, Double],
  geometry~ : Bool,
  trailing? : Double = 0,
  advances? : Array[(Double, Double)],
) -> (Double, Array[PlacedRun], Array[PlacedImage], Array[Caret]) raise @failure.Failure {
  probe.check()
  let runs : Array[PlacedRun] = []
  let images : Array[PlacedImage] = []
  let before : Map[Int, Double] = Map([])
  let after : Map[Int, Double] = Map([])
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
  let bidi = bidi_line(paragraph, start, end)
  let mut context_start = 0
  let mut source_offset = 0
  for ch in paragraph.chars {
    if source_offset >= start {
      break
    }
    source_offset += if ch.to_int() > 0xffff { 2 } else { 1 }
    context_start += 1
  }
  let groups : Array[LineGroup] = []
  let group_chars : Array[Int] = []
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
      group_chars.push(i)
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
  for i in bidi_order(bidi) {
    if visual.last() != Some(char_groups[i]) {
      visual.push(char_groups[i])
    }
  }
  let mut width = 0.0
  for index in visual {
    let group = groups[index]
    if group.image is Some(image) {
      if advances is Some(values) {
        let index = start + group.start
        let (width, gap) = values[index]
        values[index] = (width + image.width, gap)
      }
      if geometry {
        after[start + group.start] = width +
          (if group.level % 2 == 0 { 0.0 } else { image.width })
        before[start + group.end] = width +
          (if group.level % 2 == 0 { image.width } else { 0.0 })
        images.push({
          key: image.key,
          x: width,
          y: 0,
          width: image.width,
          height: image.height,
        })
      }
      width += image.width
      continue
    }
    let fragment = text[group.start:group.end].to_owned()
    let spacing : Map[Int, Double] = Map([])
    for offset, gap in spaces {
      if offset > start + group.start &&
        offset <= start + group.end &&
        (offset < end || (offset == end && trailing > 0)) {
        spacing[offset - start - group.start] = gap
      }
    }
    let advances = advances.map(values => (values, start + group.start))
    let batch = probe.shape_paragraph(
      fragment,
      group.style.size,
      "und",
      group.font,
      bidi_slice(bidi, group.start, group.end),
      geometry~,
      caret_units=120,
      spacing~,
      advances?,
      context=(paragraph.chars, context_start + group_chars[index]),
    )
    guard batch.diagnostics.is_empty() else {
      @failure.reject(
        "missing-glyph", "Preview requires every glyph; unsupported or missing glyph in paragraph",
      )
    }
    // Writer places integer-twip text portions; break-query advances stay floating.
    let portion_width = (batch.width * 20).floor() / 20
    if !geometry {
      width += portion_width
      continue
    }
    for caret in batch.carets {
      let offset = start + group.start + caret.offset
      if caret.offset > 0 {
        before[offset] = width + caret.before
      }
      if caret.offset < fragment.length() {
        after[offset] = width + caret.after
      }
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
      start: start + group.start,
      sources,
      color: group.style.color,
      size: group.style.size,
      text: fragment,
      glyphs: batch.glyphs,
      bidi: batch.runs,
      x: width,
      baseline: 0,
    })
    width += portion_width
  }
  let carets = if geometry {
    boundaries
    .filter(offset => offset >= start && offset <= end)
    .map(offset => {
      let a = after.get(offset).unwrap_or(before.get(offset).unwrap_or(0))
      let b = before.get(offset).unwrap_or(a)
      {
        offset,
        before: (if b < 0 { (b * 20).ceil() } else { (b * 20).floor() }) / 20,
        after: (if a < 0 { (a * 20).ceil() } else { (a * 20).floor() }) / 20,
      }
    })
  } else {
    []
  }
  (width, runs, images, carets)
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
) -> Array[MeasuredLine] raise @failure.Failure {
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
  let bidi = bidi_controls(@bidi.process(text))
  let spaces = script_spaces(spans, text, bidi)
  let size = if size > 0 { size } else { 11 }
  let (line_height, _, clip) = paragraph.line.metrics(
    if ascent > 0 {
      ascent
    } else {
      size * 0.8
    },
    if descent > 0 {
      descent
    } else {
      size * 0.2
    },
  )
  guard line_height > 0 &&
    (match paragraph.line {
      Exact(value) => value > 0 && !value.is_inf()
      Auto(value) | AtLeast(value) => value >= 0 && !value.is_inf()
    }) &&
    paragraph.left >= 0 &&
    paragraph.right >= 0 &&
    available - paragraph.left - paragraph.right - paragraph.first.max(0) > 0 else {
    @failure.reject("invalid-style", "Paragraph has no usable line area")
  }
  let lines : Array[MeasuredLine] = []
  let breaks = @linebreak.linebreaks(text)
  let graphemes = @linebreak.grapheme_indices_uax29(text)
  let boundaries = [0, ..graphemes.map(range => range.1)]
  let legal : Map[Int, Bool] = Map([])
  let advances = Array::make(text.length() + 1, (0.0, 0.0))
  let mut segment = 0
  for (boundary, kind) in breaks {
    // LibreOffice's offset+1 query skips ordinary breaks before surrogate pairs.
    if kind is @linebreak.Allowed &&
      boundary + 1 < text.length() &&
      text[boundary] >= 0xd800 &&
      text[boundary] <= 0xdbff &&
      text[boundary + 1] >= 0xdc00 &&
      text[boundary + 1] <= 0xdfff {
      continue
    }
    legal[boundary] = kind is @linebreak.Mandatory
    if kind is @linebreak.Mandatory {
      let visible = if boundary > segment &&
        (text[boundary - 1] == 10 || text[boundary - 1] == 12) {
        boundary - 1
      } else {
        boundary
      }
      ignore(
        measure_line(
          probe,
          spans,
          bidi,
          segment,
          visible,
          boundaries,
          spaces,
          geometry=false,
          advances~,
        ),
      )
      segment = boundary
    }
  }
  if segment < text.length() {
    ignore(
      measure_line(
        probe,
        spans,
        bidi,
        segment,
        text.length(),
        boundaries,
        spaces,
        geometry=false,
        advances~,
      ),
    )
  }
  let mut start = 0
  let mut first_grapheme = 0
  while start < text.length() || lines.is_empty() {
    let indent = paragraph.left + (if start == 0 { paragraph.first } else { 0 })
    let limit = available - indent - paragraph.right
    let mut end = start
    let mut forced = false
    let mut ordinary = start
    let mut width = 0.0
    for i in first_grapheme..<graphemes.length() {
      let (a, b) = graphemes[i]
      for offset in a..<b {
        width += advances[offset].0
        if offset > start {
          width += advances[offset].1
        }
      }
      if width > limit {
        break
      }
      end = b
      if legal.get(b) is Some(mandatory) {
        ordinary = b
        if mandatory {
          forced = true
          break
        }
      }
    }
    if !forced && ordinary > start {
      end = ordinary
    }
    if end == start && start < text.length() {
      end = graphemes[first_grapheme].1
    }
    let fitted_width = for ;; {
      let visible = if forced &&
        end > start &&
        (text[end - 1] == 10 || text[end - 1] == 12) {
        end - 1
      } else {
        end
      }
      let actual = measure_line(
          probe,
          spans,
          bidi,
          start,
          visible,
          boundaries,
          spaces,
          geometry=false,
        ).0
      if actual <= limit {
        break actual
      }
      let previous = boundaries
        .filter(offset => offset > start && offset < end)
        .last()
      guard previous is Some(previous) else {
        @failure.reject(
          "layout-overflow", "A grapheme or inline image exceeds line width",
        )
      }
      end = previous
      for (boundary, _) in breaks {
        if boundary > start && boundary <= previous && legal.contains(boundary) {
          end = boundary
        }
      }
      forced = legal.get(end) == Some(true)
    }
    let page_break = end > start && text[end - 1] == 12
    let visible_end = if forced &&
      end > start &&
      (text[end - 1] == 10 || page_break) {
      end - 1
    } else {
      end
    }
    let (width, runs, images, carets) = measure_line(
      probe,
      spans,
      bidi,
      start,
      visible_end,
      boundaries,
      spaces,
      trailing=if spaces.get(visible_end) is Some(gap) {
        if fitted_width + gap <= limit {
          gap
        } else {
          0.0
        }
      } else {
        0.0
      },
      geometry=true,
    )
    guard width <= limit else {
      @failure.reject(
        "layout-overflow", "A grapheme or inline image exceeds line width",
      )
    }
    let mut line_ascent = 0.0
    let mut line_descent = 0.0
    for run in runs {
      for range in run.bidi {
        let (a, d) = probe.line_metrics(range.font, run.size)
        line_ascent = line_ascent.max(a)
        line_descent = line_descent.max(d)
      }
    }
    if line_ascent + line_descent == 0 && images.is_empty() {
      line_ascent = if ascent > 0 { ascent } else { size * 0.8 }
      line_descent = if descent > 0 { descent } else { size * 0.2 }
    }
    let (line_height, line_baseline, _) = paragraph.line.metrics(
      line_ascent, line_descent,
    )
    let height = if clip {
      line_height
    } else {
      images
      .iter()
      .fold(init=line_height, (height, image) => {
        height.max(image.height + line_descent)
      })
    }
    let baseline = if clip || images.is_empty() {
      line_baseline
    } else {
      height - line_descent
    }
    let alignment = match paragraph.align {
      "center" => (limit - width).max(0) / 2
      "right" => (limit - width).max(0)
      _ => 0.0
    }
    lines.push({
      textHeight: line_ascent + line_descent,
      line: {
        paragraph: paragraph.id,
        container: paragraph.container,
        baseLevel: bidi.base_level,
        text: text[start:visible_end].to_owned(),
        start,
        end,
        x: indent + alignment,
        areaX: 0,
        areaWidth: available,
        y: if page_break {
          -1
        } else {
          0
        },
        width,
        height,
        clip,
        runs: runs.map(run => { ..run, baseline, }),
        images: images.map(image => { ..image, y: baseline - image.height, }),
        carets,
        readOnlyReason: paragraph.readOnlyReason,
      },
    })
    guard end > start || start == text.length() else {
      @failure.reject("layout-failed", "Line breaker made no progress")
    }
    start = end
    while first_grapheme < graphemes.length() &&
          graphemes[first_grapheme].1 <= start {
      first_grapheme += 1
    }
  }
  if text.has_suffix("\n") {
    lines.push({
      textHeight: line_height,
      line: {
        paragraph: paragraph.id,
        container: paragraph.container,
        baseLevel: bidi.base_level,
        text: "",
        start,
        end: start,
        x: paragraph.left,
        areaX: 0,
        areaWidth: available,
        y: 0,
        width: 0,
        height: line_height,
        clip,
        runs: [],
        images: [],
        carets: [{ offset: start, before: 0, after: 0, }],
        readOnlyReason: paragraph.readOnlyReason,
      },
    })
  }
  lines
}

///|
