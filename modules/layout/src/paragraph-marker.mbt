///|
priv struct MeasuredMarker {
  run : PlacedRun
  image : PlacedImage?
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
    ["tab", "space", "nothing", "presentation-rtl"].contains(marker.suffix) &&
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
  let font = if marker.image is Some(image) {
    guard marker.text.is_empty() &&
      marker.numbering is None &&
      image.x == 0 &&
      image.y == 0 else {
      @failure.reject(
        "invalid-style", "Image markers require only an unpositioned image",
      )
    }
    DrawingFrame::{
      width: image.width,
      height: image.height,
      effectExtent: (0, 0, 0, 0),
      anchor: None,
      content: Picture(image.key, [0, 0, 0, 0]),
    }.validate()
    None
  } else {
    guard font_profile_identity(profile, style.font) is Some(identity) else {
      @failure.reject(
        "missing-font",
        "Missing marker font profile mapping: " + style.font,
      )
    }
    Some(self.font_index(identity))
  }
  let batch = font.map(font => {
    let text = style.display_text(marker.text)
    let face = self.fonts[font]
    // Microsoft symbol cmaps alias legacy marker bytes into the private-use block.
    let painted = if face.symbol_cmap {
      String::from_array(
        text
        .iter()
        .map(ch => {
          let code = ch.to_uint()
          if code <= 0xffU &&
            face.font.glyph_for_codepoint(code) is Ok(None | Some(0U)) &&
            face.font.glyph_for_codepoint(code + 0xf000U) is Ok(Some(id)) &&
            id != 0U {
            (ch.to_int() + 0xf000).to_char().unwrap()
          } else {
            ch
          }
        })
        .collect(),
      )
    } else {
      text
    }
    self.shape(
      painted,
      style.render_size(),
      "und",
      primary=font,
      base=if paragraph.rtl { 1 } else { 0 },
      kerning=style.kerning,
    )
  })
  guard batch.map(b => b.diagnostics.is_empty()).unwrap_or(true) else {
    @failure.reject("missing-glyph", "Paragraph marker requires every glyph")
  }
  let width = marker.image
    .map(image => image.width)
    .unwrap_or_else(() => (batch.unwrap().width * 20).floor() / 20)
  let anchor = paragraph.left + paragraph.first
  let left = anchor -
    (match marker.align {
      "right" => width
      "center" => width / 2
      _ => 0
    })
  let end = left + width
  let space = if marker.suffix == "space" {
    let font = if font is Some(font) {
      font
    } else {
      guard paragraph.spans.get(0) is Some(span) &&
        font_profile_identity(profile, span.style.font) is Some(identity) else {
        @failure.reject("missing-font", "Missing image marker suffix font")
      }
      self.font_index(identity)
    }
    self.shape(" ", style.render_size(), "und", primary=font).width
  } else {
    0.0
  }
  let indent = match marker.suffix {
    "nothing" => end
    "space" => end + space
    "presentation-rtl" => anchor + paragraph.left.max(width)
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
  for range in batch.map(b => b.runs).unwrap_or([]) {
    let (a, d) = self.line_metrics(
      range.font,
      style.render_size(),
      leading=style.fontLeading,
    )
    let (na, nd) = self.line_metrics(
      range.font,
      style.size,
      leading=style.fontLeading,
    )
    ascent = ascent.max(na).max(a + style.rise())
    descent = descent.max(nd).max(d - style.rise())
  }
  let span : Span = {
    node: paragraph.id,
    text: marker.text,
    style,
    drawing: None,
    field: "",
  }
  Some({
    image: marker.image,
    run: {
      start: 0,
      sources: [],
      color: style.color,
      size: style.render_size(),
      text: style.display_text(marker.text),
      glyphs: batch
      .map(b => self.bold_glyphs(b.glyphs, style.font))
      .unwrap_or([]),
      bidi: batch.map(b => b.runs).unwrap_or([]),
      x: 0,
      baseline: 0,
      nominalSize: style.size,
      rise: style.rise(),
      decorations: if font is Some(font) {
        line_decorations(
          batch.unwrap().carets,
          [{ span, start: 0, end: marker.text.length(), font, }],
          0,
          width,
          end=marker.text.length(),
        )
      } else {
        []
      },
    },
    indent,
    delta: left - indent,
    width,
    ascent,
    descent,
    text: if marker.image is Some(_) {
      ""
    } else {
      style.display_text(marker.text) +
      (match marker.suffix {
        "tab" | "presentation-rtl" => "\t"
        "space" => " "
        _ => ""
      })
    },
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
