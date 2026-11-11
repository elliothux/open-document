///|
fn Object::paragraph_flow(
  self : Object,
  index : Int32,
  scale : Double,
) -> @layout.Paragraph raise @failure.Failure {
  let paragraph = self.paragraphs[index]
  let scaled_size = fn(size : Double) {
    let value = size * scale
    // Native stored/computed autofit rounds text to whole points, with a 1pt floor.
    if self.body.fit == "shrink" &&
      (self.body.fontScale is Some(_) || scale != 1) {
      value.round().max(1)
    } else {
      value
    }
  }
  let marker_size = if paragraph.bullet_size.unit == "point" {
    paragraph.bullet_size.value
  } else {
    scaled_size(paragraph.runs[0].style().size) *
    paragraph.bullet_size.value /
    100
  }
  let spans : Array[@layout.Span] = []
  for run in paragraph.runs {
    for (style, text) in run.parts {
      spans.push({
        node: run.source.map(item => item.node.id).unwrap_or(0),
        text: text.replace_all(old="\u2028", new="\n"),
        drawing: run.math.map(formula => {
          width: 0,
          height: 0,
          effectExtent: (0, 0, 0, 0),
          anchor: None,
          content: @layout.Math(
            @layout.MathFormula::new(
              formula.expression,
              { ..formula.style, size: scaled_size(formula.style.size), },
              display=formula.display,
            ),
          ),
        }),
        field: "",
        style: { ..style, size: scaled_size(style.size), },
      })
    }
  }
  let spacing : @layout.LineSpacing = match paragraph.spacing {
    Exact(value) => Exact((value * scale).max(20))
    AtLeast(value) => AtLeast(value * scale)
    // ONLYOFFICE applies the reduction before merging explicit paragraph spacing.
    Auto(value) => {
      let explicit = paragraph.source.child("pPr").bind(p => p.child("lnSpc"))
        is Some(_)
      Auto(
        (value -
        (if explicit { 0.0 } else { self.body.lineSpaceReduction * 240 })).max(
          0,
        ),
      )
    }
  }
  let flow : @layout.Paragraph = {
    id: index,
    container: 0,
    spans,
    nominalSize: spans[0].style.size,
    frame: None,
    defaultTab: paragraph.default_tab,
    tabs: paragraph.tabs.map(t => {
      position: t.position,
      align: t.align,
      leader: "none",
    }),
    decimalSymbol: ".",
    expandSoftBreak: true,
    left: paragraph.left,
    right: paragraph.right,
    first: paragraph.first,
    align: if paragraph.align == "justify" {
      "both"
    } else if paragraph.rtl && paragraph.align == "left" {
      "right"
    } else if paragraph.rtl && paragraph.align == "right" {
      "left"
    } else {
      paragraph.align
    },
    before: 0,
    after: 0,
    line: spacing,
    lineGrid: None,
    pageBreakBefore: false,
    keepLines: false,
    keepNext: false,
    widowControl: false,
    rtl: paragraph.rtl,
    marker: if paragraph.bullet.is_empty() && paragraph.picture is None {
      None
    } else {
      Some({
        text: paragraph.bullet,
        image: paragraph.picture.map(picture => {
          // ONLYOFFICE PresentationNumbering uses fontSize/4.043478260869565 millimeters.
          let height = marker_size / 4.043478260869565 * 72 / 25.4
          {
            key: picture.0,
            interpolate: None,
            x: 0,
            y: 0,
            width: height * picture.1,
            height,
          }
        }),
        numbering: None,
        style: { ..paragraph.bullet_style, size: marker_size, },
        align: "left",
        suffix: if paragraph.rtl &&
          paragraph.first < 0 &&
          paragraph.picture is None {
          "presentation-rtl"
        } else {
          "tab"
        },
      })
    },
    readOnlyReason: self.text_reason,
  }
  flow
}

///|
fn presentation_run_metrics(
  line : @layout.Line,
  probe : @layout.TextProbe,
) -> (Double, Double) raise @failure.Failure {
  let mut ascent = 0.0
  let mut descent = 0.0
  // Presentation markers do not contribute to the text ascent or descent.
  // ONLYOFFICE excludes ordinary space runs from mixed lines, but treats NBSP as text.
  let spaces = "\n \u2002\u2003\u2005\u3000\uFEFF"
  let has_text = line.runs.any(run => !run.text.trim(chars=spaces).is_empty())
  for run in line.runs {
    if has_text && run.text.trim(chars=spaces).is_empty() {
      continue
    }
    for range in run.bidi {
      let (a, d) = probe.presentation_metrics(range.font, run.nominalSize)
      ascent = ascent.max(a)
      descent = descent.max(d)
    }
  }
  (ascent, descent)
}

///|
fn presentation_line_primitives(
  line : @layout.Line,
  fonts : Array[@layout.FontInfo],
  width : Double,
  probe : @layout.TextProbe,
) -> Array[@layout.PositionedPrimitive] raise @failure.Failure {
  let (_, descent) = presentation_run_metrics(line, probe)
  line.positioned(fonts, width, underline_descent=descent)
}

///|
fn presentation_text_metrics(
  line : @layout.Line,
  paragraph : @layout.Paragraph,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> (Double, Double) raise @failure.Failure {
  let (ascent, descent) = presentation_run_metrics(line, probe)
  if ascent + descent == 0 {
    let mut end = 0
    let mut style = paragraph.spans[0].style
    for span in paragraph.spans {
      style = span.style
      end += span.text.length()
      if line.start < end {
        break
      }
    }
    guard @layout.font_profile_identity(profile, style.font) is Some(identity) else {
      @failure.reject("missing-font", "Missing empty presentation line font")
    }
    return probe.presentation_metrics(probe.font_index(identity), style.size)
  }
  (ascent, descent)
}

///|
fn presentation_exact_baseline(
  line : @layout.Line,
  paragraph : @layout.Paragraph,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Double raise @failure.Failure {
  let (ascent, descent) = presentation_text_metrics(
    line, paragraph, probe, profile,
  )
  // Native non-document paragraphs keep at least three quarters of the line above its baseline.
  (line.height * 0.75).max(ascent.min(line.height - descent))
}

///|
fn presentation_bold_pens(lines : Array[@layout.Line]) -> Array[@layout.Line] {
  let result : Array[@layout.Line] = Array(capacity=lines.length())
  let mut pen = -1.0
  let mut bold = false
  let reset = fn() {
    pen = -1
    bold = false
  }
  let paint_run = fn(run : @layout.PlacedRun) {
    if run.glyphs.all(glyph => glyph.strokeWidth == 0) {
      if !run.glyphs.is_empty() {
        bold = false
      }
      return run
    }
    let glyphs = run.glyphs.map(glyph => {
      if glyph.strokeWidth == 0 {
        bold = false
        return glyph
      }
      let width = glyph.strokeWidth * glyph.scale
      if !bold {
        // The native writer changes the pen when entering fill-and-stroke.
        if (width - pen).abs() > 0.001 {
          pen = width
        }
        bold = true
      }
      if pen == width {
        glyph
      } else {
        { ..glyph, strokeWidth: pen / glyph.scale, }
      }
    })
    { ..run, glyphs, }
  }
  let mut first = 0
  while first < lines.length() {
    let mut end = first + 1
    while end < lines.length() && lines[end].paragraph == lines[first].paragraph {
      end += 1
    }
    let paragraph = lines[first:end]
    let mut highlighted = false
    let mut decorated = false
    // Native drawing paints paragraph highlights before text and rules after it.
    for line in paragraph {
      for runs in [line.marker, line.runs] {
        for run in runs {
          for decoration in run.decorations {
            highlighted = highlighted || !decoration.highlight.is_empty()
            decorated = decorated || decoration.underline || decoration.strike
          }
        }
      }
    }
    if highlighted {
      reset()
    }
    for line in paragraph {
      if line.markerImage is Some(_) {
        reset()
      }
      if line.drawings.any(drawing => drawing.anchor is None) {
        // shortcut: inline drawings keep independent pens until their native paint order is resolved.
        reset()
        result.push(line)
      } else {
        let marker = line.marker.map(paint_run)
        let runs = line.runs.map(paint_run)
        result.push({ ..line, marker, runs, })
      }
    }
    if decorated {
      reset()
    }
    first = end
  }
  result
}
