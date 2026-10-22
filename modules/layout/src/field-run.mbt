///|
fn Span::logical_text(self : Span) -> String {
  if self.field.is_empty() {
    self.text
  } else {
    "\ufffc"
  }
}

///|
fn LineGroup::measure_field(
  self : LineGroup,
  probe : TextProbe,
  position : Int,
  width : Double,
  rtl : Bool,
  geometry : Bool,
) -> (Double, PlacedRun?) raise @failure.Failure {
  let (node, value) = self.field.unwrap()
  let batch = probe.shape_paragraph(
    value,
    self.style.render_size(),
    "und",
    self.font,
    @bidi.process(value),
    geometry~,
    caret_units=120,
    tracking=self.style.spacing,
  )
  guard batch.diagnostics.is_empty() else {
    @failure.reject("missing-glyph", "Page field requires every result glyph")
  }
  let advance = (batch.width * 20).floor() / 20
  if !geometry {
    return (advance, None)
  }
  let decorations : Array[TextDecoration] = if advance > 0 &&
    (
      self.style.underline ||
      self.style.strike ||
      !self.style.highlight.is_empty()
    ) {
    [
      {
        x: 0,
        width: advance,
        underline: self.style.underline,
        strike: self.style.strike,
        highlight: self.style.highlight,
      },
    ]
  } else {
    []
  }
  (
    advance,
    Some({
      start: position,
      sources: [{ node, start: 0, end: 1, offset: 0, }],
      color: self.style.color,
      size: self.style.render_size(),
      text: value,
      glyphs: batch.glyphs,
      bidi: batch.runs.map(run => {
        ..run,
        start: 0,
        end: 1,
        level: self.level,
      }),
      x: if rtl {
        -width - advance
      } else {
        width
      },
      baseline: 0,
      nominalSize: self.style.size,
      rise: self.style.rise(),
      decorations,
    }),
  )
}

///|
fn PlacedRun::logical_cluster(self : PlacedRun, glyph : Glyph) -> Int {
  if self.text.length() > 1 &&
    self.sources is [source] &&
    source.end - source.start == 1 {
    0
  } else {
    glyph.cluster
  }
}

///|
fn Line::display_text(self : Line, math~ : Bool = true) -> String {
  if !self.text.contains("\ufffc") {
    return self.text
  }
  let fields : Map[Int, String] = Map([])
  for image in self.drawings {
    if image.content is Fraction(fraction) {
      fields[image.start - self.start] = if math {
        "(" + fraction.numerator + ")/(" + fraction.denominator + ")"
      } else {
        ""
      }
    }
  }
  for run in self.runs {
    let offset = run.start - self.start
    // A field covers one object marker; its run retains the complete displayed result.
    if offset >= 0 &&
      offset < self.text.length() &&
      self.text[offset] == 0xfffc &&
      run.sources is [source] &&
      source.end - source.start == 1 {
      fields[offset] = run.text
    }
  }
  if fields.is_empty() {
    return self.text
  }
  let text = StringBuilder()
  for offset, ch in self.text.iter2() {
    text.write_string(fields.get(offset).unwrap_or_else(() => ch.to_string()))
  }
  text.to_string()
}
