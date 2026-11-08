///|
fn line_content_end(text : String) -> Int32 {
  let mut end = text.length()
  while end > 0 && text[end - 1] == 32 {
    end -= 1
  }
  end
}

///|
fn line_content_width(
  text : String,
  start : Int32,
  width : Double,
  carets : Array[Caret],
  rtl : Bool,
) -> Double {
  let end = line_content_end(text)
  if end == text.length() {
    return width
  }
  carets
  .iter()
  .find_first(caret => caret.offset == start + end)
  .map(caret => {
    (if rtl { width - caret.after } else { caret.after }).clamp(
      min=0,
      max=width,
    )
  })
  .unwrap_or(width)
}

///|
/// Return the fitting width while retaining trailing-space geometry and carets.
pub fn Line::content_width(self : Line) -> Double {
  line_content_width(
    self.text,
    self.start,
    self.width,
    self.carets,
    self.baseLevel % 2 == 1,
  )
}

///|
fn measure_line(
  probe : TextProbe,
  spans : Array[MeasuredSpan],
  paragraph : @bidi.BidiParagraph,
  start : Int32,
  end : Int32,
  boundaries : Array[Int32],
  spaces : Map[Int32, Double],
  geometry~ : Bool,
  ligatures~ : Bool = true,
  cell~ : Bool = false,
  writer_twips~ : Bool = true,
  trailing~ : Double = 0,
  advances? : Array[(Double, Double)],
  tabs~ : TabLayout? = None,
  rtl~ : Bool = false,
) -> (Double, Array[PlacedRun], Array[PlacedDrawingFrame], Array[Caret]) raise @failure.Failure {
  probe.check()
  let runs : Array[PlacedRun] = []
  let images : Array[PlacedDrawingFrame] = []
  let before : Map[Int32, Double] = Map([])
  let after : Map[Int32, Double] = Map([])
  let text = StringBuilder()
  for item in spans {
    let a = start.max(item.start)
    let b = end.min(item.end)
    if a < b {
      text.write_string(
        item.span.logical_text()[a - item.start:b - item.start].to_owned(),
      )
    }
  }
  let text = text.to_string()
  let decoration_end = start + line_content_end(text)
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
  let group_chars : Array[Int32] = []
  let char_groups : Array[Int32] = []
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
      group.drawing is None &&
      group.field is None &&
      item.span.drawing is None &&
      item.span.field.is_empty() &&
      !group.tab &&
      ch != '\t' &&
      group.font == item.font &&
      font_requests_bold(group.style.font) ==
      font_requests_bold(item.span.style.font) &&
      group.style.size == item.span.style.size &&
      group.style.color == item.span.style.color &&
      group.style.script == item.span.style.script &&
      group.style.spacing == item.span.style.spacing &&
      group.style.kerning == item.span.style.kerning &&
      group.style.fontLeading == item.span.style.fontLeading &&
      group.style.caps == item.span.style.caps &&
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
        drawing: item.span.drawing,
        field: if item.span.field.is_empty() {
          None
        } else {
          Some((item.span.node, item.span.text))
        },
        tab: ch == '\t',
      })
    }
    char_groups.push(groups.length() - 1)
    offset = next
  }
  let visual : Array[Int32] = []
  for i in bidi_order(bidi) {
    if visual.last() != Some(char_groups[i]) {
      visual.push(char_groups[i])
    }
  }
  let mut width = 0.0
  let mut leader_glyphs = 0
  for index in (if rtl { visual.rev() } else { visual }) {
    let group = groups[index]
    if group.tab {
      let stop = tabs.unwrap_or({
        interval: 36,
        stops: [],
        decimalSymbol: ".",
        origin: 0,
        left: 0,
        limit: 1000000000,
      })
      let (following, decimal) = if stop.needs_following(width) {
        let segment_end = tab_segment_end(text, group.end)
        let point = tab_decimal(
          text,
          group.end,
          segment_end,
          stop.decimalSymbol,
        )
        let measured = if group.end == segment_end {
          (0.0, [], [], [])
        } else {
          measure_line(
            probe,
            spans,
            paragraph,
            start + group.end,
            start + segment_end,
            boundaries,
            spaces,
            geometry=rtl && stop.next(width).align == "decimal",
            ligatures~,
            cell~,
            writer_twips~,
          )
        }
        let following = measured.0
        let decimal = if rtl && stop.next(width).align == "decimal" {
          measured.3
          .iter()
          .find_first(caret => caret.offset == start + point)
          .map(caret => following - caret.after)
          .unwrap_or(0)
        } else if point == segment_end {
          following
        } else if point == group.end {
          0.0
        } else {
          measure_line(
            probe,
            spans,
            paragraph,
            start + group.end,
            start + point,
            boundaries,
            spaces,
            geometry=false,
            ligatures~,
            cell~,
            writer_twips~,
          ).0
        }
        (following, decimal)
      } else {
        (0.0, 0.0)
      }
      let advance = stop.advance(width, following~, decimal~)
      if advances is Some(values) {
        values[start + group.start] = (advance, 0)
      }
      if geometry {
        after[start + group.start] = width
        before[start + group.end] = width + advance
        let run = group.tab_run(
          probe,
          advance,
          if rtl {
            -width - advance
          } else {
            width
          },
          start + group.start,
          spans,
          stop.next(width).leader,
        )
        leader_glyphs += run.glyphs.length()
        guard leader_glyphs <= 16384 else {
          @failure.reject("limit-exceeded", "Line leader glyph budget exceeded")
        }
        runs.push(run)
      }
      width += advance
      continue
    }
    if group.field is Some(_) {
      let position = start + group.start
      let (advance, run) = group.measure_field(
        probe, position, width, rtl, geometry,
      )
      if advances is Some(values) {
        values[position] = (advance, 0)
      }
      if run is Some(run) {
        let from_end = (group.level % 2 == 1) != rtl
        after[position] = width + (if from_end { advance } else { 0 })
        before[start + group.end] = width + (if from_end { 0 } else { advance })
        runs.push(run)
      }
      width += advance
      continue
    }
    if group.drawing is Some(image) {
      let advance = if image.anchor is Some(_) {
        0.0
      } else {
        image.width + image.effectExtent.0 + image.effectExtent.2
      }
      if advances is Some(values) {
        let index = start + group.start
        let (width, gap) = values[index]
        values[index] = (width + advance, gap)
      }
      if geometry {
        after[start + group.start] = width +
          (if (group.level % 2 == 0) != rtl { 0.0 } else { advance })
        before[start + group.end] = width +
          (if (group.level % 2 == 0) != rtl { advance } else { 0.0 })
        images.push({
          content: image.content.copy(),
          start: start + group.start,
          level: group.level,
          x: if rtl {
            -width - advance + image.effectExtent.0
          } else {
            width + image.effectExtent.0
          },
          y: 0,
          width: image.width,
          height: image.height,
          effectExtent: image.effectExtent,
          anchor: image.anchor,
        })
      }
      width += advance
      continue
    }
    let fragment = text[group.start:group.end].to_owned()
    let spacing : Map[Int32, Double] = Map([])
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
      group.style.render_size(),
      "und",
      group.font,
      bidi_slice(bidi, group.start, group.end),
      geometry~,
      caret_units=120,
      spacing~,
      advances?,
      context=(paragraph.chars, context_start + group_chars[index]),
      tracking=group.style.spacing,
      kerning=group.style.kerning,
      ligatures~,
      caps=group.style.caps,
      cell~,
    )
    guard batch.diagnostics.is_empty() else {
      @failure.reject(
        "missing-glyph", "Preview requires every glyph; unsupported or missing glyph in paragraph",
      )
    }
    // Writer places integer-twip text portions, unlike presentation frames.
    let portion_width = if writer_twips {
      (batch.width * 20).floor() / 20
    } else {
      batch.width
    }
    if !geometry {
      width += portion_width
      continue
    }
    for caret in batch.carets {
      let offset = start + group.start + caret.offset
      if caret.offset > 0 {
        before[offset] = width +
          (if rtl { portion_width - caret.before } else { caret.before })
      }
      if caret.offset < fragment.length() {
        after[offset] = width +
          (if rtl { portion_width - caret.after } else { caret.after })
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
      size: group.style.render_size(),
      nominalSize: group.style.size,
      rise: group.style.rise(),
      decorations: line_decorations(
        batch.carets,
        spans,
        start + group.start,
        portion_width,
        end=decoration_end,
      ),
      text: group.style.display_text(fragment),
      glyphs: probe.bold_glyphs(batch.glyphs, group.style.font),
      bidi: batch.runs,
      x: if rtl {
        -width - portion_width
      } else {
        width
      },
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
      let a = if rtl { width - a } else { a }
      let b = if rtl { width - b } else { b }
      {
        offset,
        before: if writer_twips {
          (if b < 0 { (b * 20).ceil() } else { (b * 20).floor() }) / 20
        } else {
          b
        },
        after: if writer_twips {
          (if a < 0 { (a * 20).ceil() } else { (a * 20).floor() }) / 20
        } else {
          a
        },
      }
    })
  } else {
    []
  }
  // Reflect placements, retaining each shaped run's glyph order and local geometry.
  let runs = if rtl {
    runs.rev().map(run => { ..run, x: width + run.x, })
  } else {
    runs
  }
  let images = if rtl {
    images.rev().map(image => { ..image, x: width + image.x, })
  } else {
    images
  }
  (width, runs, images, carets)
}
