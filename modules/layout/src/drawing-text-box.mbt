///|
pub(all) struct DrawingTextBoxProperties {
  insets : Array[Double]
  anchor : String
  wrap : Bool
  clip : Bool
} derive(ToJson)

///|
pub extend DrawingTextBoxProperties with ToJson::{to_json}

///|
pub struct DrawingTextBox {
  paragraphs : Array[Paragraph]
  insets : Array[Double]
  anchor : String
  wrap : Bool
  clip : Bool
  lines : Array[Line]
}

///|
/// WordprocessingShape text uses the document paragraph shaper and native styles.
/// Insets are top, right, bottom and left, in points.
pub fn DrawingTextBox::new(
  paragraphs : Array[Paragraph],
  insets : Array[Double],
  anchor : String,
  wrap : Bool,
  clip : Bool,
) -> DrawingTextBox {
  { paragraphs, insets, anchor, wrap, clip, lines: [], }
}

///|
pub fn DrawingTextBox::paragraphs(self : DrawingTextBox) -> Array[Paragraph] {
  self.paragraphs
}

///|
/// Returns the native text area settings; insets are top, right, bottom and left in points.
pub fn DrawingTextBox::properties(
  self : DrawingTextBox,
) -> DrawingTextBoxProperties {
  {
    insets: self.insets,
    anchor: self.anchor,
    wrap: self.wrap,
    clip: self.clip,
  }
}

///|
pub impl ToJson for DrawingTextBox with fn to_json(self) {
  {
    "paragraphs": self.paragraphs,
    "insets": self.insets,
    "anchor": self.anchor,
    "wrap": self.wrap,
    "clip": self.clip,
  }
}

///|
pub extend DrawingTextBox with ToJson::{to_json}

///|
fn DrawingTextBox::copy(self : DrawingTextBox) -> DrawingTextBox {
  { ..self, lines: self.lines.map(line => line.copy_geometry()), }
}

///|
fn DrawingTextBox::validate(
  self : DrawingTextBox,
) -> Unit raise @failure.Failure {
  guard self.insets.length() == 4 &&
    self.insets.all(v => !v.is_nan() && !v.is_inf() && v >= 0 && v <= 14400) &&
    ["t", "ctr", "b"].contains(self.anchor) &&
    self.paragraphs.length() > 0 &&
    self.paragraphs.length() <= 256 else {
    @failure.reject("invalid-drawing", "Invalid text box body")
  }
  let mut units = 0
  for paragraph in self.paragraphs {
    guard paragraph.spans.all(span => {
        span.drawing is None && span.field.is_empty()
      }) &&
      paragraph.marker is None else {
      @failure.reject(
        "unsupported-layout", "Nested drawings fields and lists require text box support",
      )
    }
    units += paragraph.spans
      .iter()
      .fold(init=0, (sum, span) => sum + span.text.length())
    guard units <= 32767 else {
      @failure.reject("limit-exceeded", "Text box exceeds text budget")
    }
  }
}

///|
fn DrawingFrame::prepare_text(
  self : DrawingFrame,
  probe : TextProbe,
  profile : Map[String, String],
) -> DrawingFrame raise @failure.Failure {
  if self.content is Fraction(fraction) {
    return fraction.prepare(probe, profile)
  }
  if self.content is Scripts(scripts) {
    return scripts.prepare(probe, profile)
  }
  guard self.content is TextBox(shape, text) else { return self }
  let area = self.text_box_rect(shape, text)
  let left = area.x
  let top = area.y
  let bottom = self.height - area.y - area.height
  let width = area.width
  let lines : Array[Line] = []
  let cache = ParagraphCache::new(probe, profile)
  let mut y = top
  let mut after = 0.0
  let mut gap = 0.0
  let mut terminal = 0.0
  for paragraph in text.paragraphs {
    paragraph.validate_spacing(14400)
    let measured = cache.lines(probe, paragraph, profile, width, wrap=text.wrap)
    y += after.max(paragraph.before) + gap
    for index, item in measured {
      let line = item.spaced(paragraph.line, index == 0)
      lines.push({
        ..line,
        x: line.x + left,
        y,
        areaX: left,
        areaWidth: width,
        runs: line.runs.map(run => {
          ..run,
          x: run.x + line.x + left,
          baseline: run.baseline + y,
        }),
        bars: line.bars.map(x => x + left),
        carets: line.carets.map(c => {
          ..c,
          before: c.before + line.x + left,
          after: c.after + line.x + left,
        }),
      })
      y += line.height
      gap = paragraph.line.gap(item.textHeight)
    }
    after = paragraph.after
    terminal = paragraph.line.terminal_gap(paragraph.nominalSize)
  }
  y += after + terminal
  let spare = (self.height - bottom - y).max(0)
  let offset = if text.anchor == "b" {
    spare
  } else if text.anchor == "ctr" {
    spare / 2
  } else {
    0.0
  }
  {
    ..self,
    content: TextBox(shape, {
      ..text,
      lines: lines.map(line => {
        ..line,
        y: line.y + offset,
        runs: line.runs.map(run => { ..run, baseline: run.baseline + offset, }),
      }),
    }),
  }
}

///|
fn DrawingFrame::text_box_rect(
  self : DrawingFrame,
  shape : BasicShape,
  text : DrawingTextBox,
) -> Border raise @failure.Failure {
  // ONLYOFFICE applies the preset text rectangle before DrawingML body insets.
  let inset = if shape.preset == "ellipse" {
    (1.0 - 0.7071067811865476) / 2
  } else {
    0.0
  }
  let left = text.insets[3] + self.width * inset
  let right = text.insets[1] + self.width * inset
  let top = text.insets[0] + self.height * inset
  let bottom = text.insets[2] + self.height * inset
  let width = self.width - left - right
  guard width > 0 && self.height > top + bottom else {
    @failure.reject("layout-overflow", "Text box has no usable text area")
  }
  { x: left, y: top, width, height: self.height - top - bottom, }
}
