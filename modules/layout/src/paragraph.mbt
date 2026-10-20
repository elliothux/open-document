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
priv struct LineGroup {
  start : Int
  end : Int
  font : Int
  style : TextStyle
  level : Int
  image : InlineImage?
  tab : Bool
}

///|
fn paragraph_lines(
  probe : TextProbe,
  paragraph : Paragraph,
  profile : Map[String, String],
  available : Double,
  baseLevel? : Int,
  inTable~ : Bool = false,
  startOffset~ : Int = 0,
  wrap~ : Bool = true,
) -> Array[MeasuredLine] raise @failure.Failure {
  guard paragraph.defaultTab >= 0 && paragraph.defaultTab <= 1584 else {
    @failure.reject("invalid-style", "Invalid default tab interval")
  }
  validate_tabs(paragraph.tabs)
  let marker = if startOffset == 0 {
    probe.paragraph_marker(paragraph, profile, available)
  } else {
    None
  }
  let paragraph = if marker is Some(marker) {
    { ..paragraph, first: marker.indent - paragraph.left, }
  } else {
    paragraph
  }
  guard paragraph.decimalSymbol.iter().count() == 1 &&
    !paragraph.decimalSymbol.trim().is_empty() &&
    !paragraph.decimalSymbol.contains("\t") &&
    !paragraph.decimalSymbol.contains("\n") else {
    @failure.reject("invalid-style", "Invalid decimal tab symbol")
  }
  let spans : Array[MeasuredSpan] = []
  let text = StringBuilder()
  let mut length = 0
  let mut size = 0.0
  let mut ascent = 0.0
  let mut descent = 0.0
  for span in paragraph.spans {
    // ONLYOFFICE retains cell page/column-break offsets without forcing a line.
    let span = if inTable &&
      (span.text.contains("\u000b") || span.text.contains("\u000c")) {
      {
        ..span,
        text: span.text
        .replace_all(old="\u000b", new="\u2060")
        .replace_all(old="\u000c", new="\u2060"),
      }
    } else {
      span
    }
    if span.image is Some(image) {
      guard image.crop.length() == 4 &&
        image.crop.all(v => !v.is_nan() && !v.is_inf() && v >= 0 && v < 1) &&
        image.crop[0] + image.crop[2] < 1 &&
        image.crop[1] + image.crop[3] < 1 else {
        @failure.reject("invalid-image", "Invalid inline image crop")
      }
    }
    guard ["baseline", "subscript", "superscript"].contains(span.style.script) &&
      (
        span.style.highlight.is_empty() ||
        (
          span.style.highlight.length() == 6 &&
          span.style.highlight.iter().all(ch => ch.is_ascii_hexdigit())
        )
      ) else {
      @failure.reject("invalid-style", "Invalid text decoration")
    }
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
  guard startOffset >= 0 && startOffset <= text.length() else {
    @failure.reject(
      "invalid-operation", "Invalid paragraph continuation offset",
    )
  }
  let source_text = if inTable {
    paragraph.spans.map(span => span.text).join("")
  } else {
    text
  }
  let bidi = bidi_controls(
    if baseLevel == Some(0) {
      @bidi.process(text, direction=@bidi.LTR)
    } else if baseLevel == Some(1) || paragraph.rtl {
      @bidi.process(text, direction=@bidi.RTL)
    } else {
      @bidi.process(text)
    },
  )
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
    available -
    paragraph.left -
    paragraph.right -
    (if startOffset == 0 { paragraph.first.max(0) } else { 0 }) >
    0 else {
    @failure.reject("invalid-style", "Paragraph has no usable line area")
  }
  let lines : Array[MeasuredLine] = []
  let bars = paragraph.tabs
    .filter(stop => stop.align == "bar" && stop.position <= available)
    .map(stop => {
      if paragraph.rtl {
        available - stop.position
      } else {
        stop.position
      }
    })
  let mut leader_glyphs = 0
  let breaks = @linebreak.linebreaks(text)
  let graphemes = @linebreak.grapheme_indices_uax29(text)
  let boundaries = [0, ..graphemes.map(range => range.1)]
  let legal : Map[Int, Bool] = Map([])
  let advances = Array::make(text.length() + 1, (0.0, 0.0))
  let mut segment = startOffset
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
    if boundary <= startOffset {
      continue
    }
    if kind is @linebreak.Mandatory {
      let visible = if boundary > segment &&
        (
          text[boundary - 1] == 10 ||
          text[boundary - 1] == 11 ||
          text[boundary - 1] == 12
        ) {
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
          rtl=paragraph.rtl,
          tabs=Some({
            interval: paragraph.defaultTab,
            stops: paragraph.tabs,
            decimalSymbol: paragraph.decimalSymbol,
            origin: paragraph.left +
            (if segment == 0 { paragraph.first } else { 0 }),
            left: paragraph.left,
            limit: available - paragraph.right,
          }),
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
        rtl=paragraph.rtl,
        tabs=Some({
          interval: paragraph.defaultTab,
          stops: paragraph.tabs,
          decimalSymbol: paragraph.decimalSymbol,
          origin: paragraph.left +
          (if segment == 0 { paragraph.first } else { 0 }),
          left: paragraph.left,
          limit: available - paragraph.right,
        }),
      ),
    )
  }
  let mut start = startOffset
  let mut first_grapheme = 0
  while first_grapheme < graphemes.length() &&
        graphemes[first_grapheme].1 <= start {
    first_grapheme += 1
  }
  guard start == 0 ||
    start == text.length() ||
    graphemes
    .get(first_grapheme)
    .map(range => range.0 == start)
    .unwrap_or(false) else {
    @failure.reject(
      "invalid-operation", "Paragraph continuation splits a grapheme",
    )
  }
  while start < text.length() || (text.is_empty() && lines.is_empty()) {
    let indent = paragraph.left + (if start == 0 { paragraph.first } else { 0 })
    // Twip-aligned widths can lose a few binary digits when subtracting cell margins.
    let limit = available - indent - paragraph.right + 0.00000001
    let mut end = start
    let mut forced = false
    let mut ordinary = start
    let mut width = 0.0
    for i in first_grapheme..<graphemes.length() {
      let (a, b) = graphemes[i]
      for offset in a..<b {
        if text[offset] == 9 {
          width += (
            {
              interval: paragraph.defaultTab,
              stops: paragraph.tabs,
              decimalSymbol: paragraph.decimalSymbol,
              origin: indent,
              left: paragraph.left,
              limit: available - paragraph.right,
            } : TabLayout).estimated_advance(width, text, offset, advances)
          continue
        }
        width += advances[offset].0
        if offset > start {
          width += advances[offset].1
        }
      }
      if wrap && width > limit {
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
        (text[end - 1] == 10 || text[end - 1] == 11 || text[end - 1] == 12) {
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
          rtl=paragraph.rtl,
          tabs=Some({
            interval: paragraph.defaultTab,
            stops: paragraph.tabs,
            decimalSymbol: paragraph.decimalSymbol,
            origin: indent,
            left: paragraph.left,
            limit: available - paragraph.right,
          }),
        ).0
      if !wrap || actual <= limit {
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
    let column_break = end > start && text[end - 1] == 11
    let region_break = column_break || (end > start && text[end - 1] == 12)
    let visible_end = if forced &&
      end > start &&
      (text[end - 1] == 10 || region_break) {
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
        if !wrap || fitted_width + gap <= limit {
          gap
        } else {
          0.0
        }
      } else {
        0.0
      },
      geometry=true,
      rtl=paragraph.rtl,
      tabs=Some({
        interval: paragraph.defaultTab,
        stops: paragraph.tabs,
        decimalSymbol: paragraph.decimalSymbol,
        origin: indent,
        left: paragraph.left,
        limit: available - paragraph.right,
      }),
    )
    guard !wrap || width <= limit else {
      @failure.reject(
        "layout-overflow", "A grapheme or inline image exceeds line width",
      )
    }
    for run in runs {
      if run.text == "\t" {
        leader_glyphs += run.glyphs.length()
      }
    }
    guard leader_glyphs <= 65536 else {
      @failure.reject(
        "limit-exceeded", "Paragraph leader glyph budget exceeded",
      )
    }
    let mut line_ascent = if start == 0 {
      marker.map(m => m.ascent).unwrap_or(0)
    } else {
      0
    }
    let mut line_descent = if start == 0 {
      marker.map(m => m.descent).unwrap_or(0)
    } else {
      0
    }
    for run in runs {
      for range in run.bidi {
        let (a, d) = probe.line_metrics(range.font, run.size)
        line_ascent = line_ascent.max(a)
        line_descent = line_descent.max(d)
        if run.rise != 0 {
          let (nominal_ascent, nominal_descent) = probe.line_metrics(
            range.font,
            run.nominalSize,
          )
          line_ascent = line_ascent.max(nominal_ascent).max(a + run.rise)
          line_descent = line_descent.max(nominal_descent).max(d - run.rise)
        }
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
        text: source_text[start:visible_end].to_owned(),
        start,
        end,
        caretOnly: region_break && visible_end == start,
        repeated: false,
        x: if paragraph.rtl {
          available - indent - alignment - width
        } else {
          indent + alignment
        },
        areaX: 0,
        areaWidth: available,
        // Negative measured Y encodes a forced region transition until placement.
        y: if column_break {
          -2
        } else if region_break {
          -1
        } else {
          0
        },
        width,
        height,
        clip,
        cellClip: None,
        justified: false,
        marker: [],
        markerText: "",
        bars,
        runs: runs.map(run => {
          ..run,
          text: source_text[run.start:run.start + run.text.length()].to_owned(),
          baseline: baseline - run.rise,
        }),
        images: images.map(image => { ..image, y: baseline - image.height, }),
        carets,
        readOnlyReason: paragraph.readOnlyReason,
      },
    })
    if paragraph.align == "both" &&
      !region_break &&
      (end < text.length() || (end > start && text[end - 1] == 10)) &&
      !(end > start && text[end - 1] == 10 && !paragraph.expandSoftBreak) {
      let last = lines.length() - 1
      lines[last] = {
        ..lines[last],
        line: {
          let line = justified_line(lines[last].line, limit)
          if paragraph.rtl && line.justified {
            { ..line, x: paragraph.right, }
          } else {
            line
          }
        },
      }
    }
    if paragraph.align == "both" &&
      !paragraph.rtl &&
      bidi.base_level % 2 == 1 &&
      !lines.last().unwrap().line.justified {
      let last = lines.length() - 1
      lines[last] = {
        ..lines[last],
        line: { ..lines[last].line, x: indent + (limit - width).max(0), },
      }
    }
    guard end > start || start == text.length() else {
      @failure.reject("layout-failed", "Line breaker made no progress")
    }
    start = end
    while first_grapheme < graphemes.length() &&
          graphemes[first_grapheme].1 <= start {
      first_grapheme += 1
    }
  }
  if text.has_suffix("\n") ||
    text.has_suffix("\u000b") ||
    text.has_suffix("\u000c") {
    lines.push({
      textHeight: line_height,
      line: {
        paragraph: paragraph.id,
        container: paragraph.container,
        baseLevel: bidi.base_level,
        text: "",
        start,
        end: start,
        caretOnly: text.has_suffix("\u000b") || text.has_suffix("\u000c"),
        repeated: false,
        x: if paragraph.rtl {
          available - paragraph.left
        } else {
          paragraph.left
        },
        areaX: 0,
        areaWidth: available,
        y: 0,
        width: 0,
        height: line_height,
        clip,
        cellClip: None,
        justified: false,
        marker: [],
        markerText: "",
        bars,
        runs: [],
        images: [],
        carets: [{ offset: start, before: 0, after: 0, }],
        readOnlyReason: paragraph.readOnlyReason,
      },
    })
  }
  if marker is Some(marker) {
    let line = lines[0].line
    let baseline = line.runs
      .get(0)
      .map(run => run.baseline + run.rise)
      .unwrap_or(paragraph.line.metrics(marker.ascent, marker.descent).1)
    lines[0] = {
      ..lines[0],
      line: {
        ..line,
        markerText: marker.text,
        caretOnly: false,
        repeated: false,
        marker: [
          {
            ..marker.run,
            x: if paragraph.rtl {
              line.width - marker.delta - marker.width
            } else {
              marker.delta
            },
            baseline: baseline - marker.run.rise,
          },
        ],
      },
    }
  }
  lines
}

///|
