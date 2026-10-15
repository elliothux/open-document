///|
priv struct MeasuredMarker {
  run : PlacedRun
  indent : Double
  delta : Double
  width : Double
  ascent : Double
  descent : Double
  text : String
}

///|
fn TextProbe::paragraph_marker(
  self : TextProbe,
  paragraph : Paragraph,
  profile : Map[String, String],
  available : Double,
) -> MeasuredMarker? raise @failure.Failure {
  guard paragraph.marker is Some(marker) else { return None }
  let style = marker.style
  guard marker.text.length() <= 256 &&
    !marker.text.iter().any(ch => ch < ' ' || ch == '\u007f') &&
    ["left", "right", "center"].contains(marker.align) &&
    ["tab", "space", "nothing"].contains(marker.suffix) &&
    style.size > 0 &&
    style.size <= 1024 &&
    style.color.length() == 6 &&
    style.color.iter().all(ch => ch.is_ascii_hexdigit()) &&
    (
      style.highlight.is_empty() ||
      (
        style.highlight.length() == 6 &&
        style.highlight.iter().all(ch => ch.is_ascii_hexdigit())
      )
    ) &&
    ["baseline", "superscript", "subscript"].contains(style.script) else {
    @failure.reject("invalid-style", "Invalid paragraph marker")
  }
  guard profile.get(style.font) is Some(identity) else {
    @failure.reject(
      "missing-font",
      "Missing marker font profile mapping: " + style.font,
    )
  }
  let font = self.font_index(identity)
  let batch = self.shape(
    marker.text,
    style.render_size(),
    "und",
    primary=font,
    base=if paragraph.rtl { 1 } else { 0 },
  )
  guard batch.diagnostics.is_empty() else {
    @failure.reject("missing-glyph", "Paragraph marker requires every glyph")
  }
  let width = (batch.width * 20).floor() / 20
  let anchor = paragraph.left + paragraph.first
  let left = anchor -
    (match marker.align {
      "right" => width
      "center" => width / 2
      _ => 0
    })
  let end = left + width
  let indent = match marker.suffix {
    "nothing" => end
    "space" =>
      end + self.shape(" ", style.render_size(), "und", primary=font).width
    _ =>
      end +
      TabLayout::{
        interval: paragraph.defaultTab,
        origin: 0,
        left: paragraph.left,
        limit: available - paragraph.right,
        stops: paragraph.tabs,
        decimalSymbol: paragraph.decimalSymbol,
      }.advance(end)
  }
  guard indent >= 0 && indent < available - paragraph.right else {
    @failure.reject("layout-overflow", "Paragraph marker leaves no text width")
  }
  let mut ascent = 0.0
  let mut descent = 0.0
  for range in batch.runs {
    let (a, d) = self.line_metrics(range.font, style.render_size())
    let (na, nd) = self.line_metrics(range.font, style.size)
    ascent = ascent.max(na).max(a + style.rise())
    descent = descent.max(nd).max(d - style.rise())
  }
  let span : Span = {
    node: paragraph.id,
    text: marker.text,
    style,
    image: None,
  }
  Some({
    run: {
      start: 0,
      sources: [],
      color: style.color,
      size: style.render_size(),
      text: marker.text,
      glyphs: batch.glyphs,
      bidi: batch.runs,
      x: 0,
      baseline: 0,
      nominalSize: style.size,
      rise: style.rise(),
      decorations: line_decorations(
        batch.carets,
        [{ span, start: 0, end: marker.text.length(), font, }],
        0,
        width,
      ),
    },
    indent,
    delta: left - indent,
    width,
    ascent,
    descent,
    text: marker.text +
    (match marker.suffix {
      "tab" => "\t"
      "space" => " "
      _ => ""
    }),
  })
}

///|
fn Line::paint_runs(self : Line) -> Array[PlacedRun] {
  if self.marker.is_empty() {
    self.runs
  } else {
    [..self.marker, ..self.runs]
  }
}
