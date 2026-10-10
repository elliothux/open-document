///|
priv struct Run {
  start : Int
  end : Int
  font : Int
  level : Int
  script : @common.Script
}

///|
pub fn TextProbe::shape(
  self : TextProbe,
  text : String,
  size : Double,
  language : String,
  primary? : Int = 0,
  base? : Int = -1,
) -> ShapeBatch raise @failure.Failure {
  self.check()
  let inserted : Array[String] = []
  let original_outline_bytes = self.outline_bytes
  errdefer {
    for key in inserted {
      self.outlines.remove(key)
    }
    self.outline_bytes = original_outline_bytes
  }
  guard !self.fonts.is_empty() else {
    @failure.reject("missing-font", "Load a font before shaping")
  }
  guard primary >= 0 && primary < self.fonts.length() else {
    @failure.reject("missing-font", "Unknown primary font")
  }
  guard text.length() <= 4096 &&
    size > 0 &&
    size <= 1024 &&
    language.length() <= 64 else {
    @failure.reject("limit-exceeded", "Text probe input exceeds budget")
  }
  guard base >= -1 && base <= 125 else {
    @failure.reject("invalid-operation", "Invalid bidi base level")
  }
  let paragraph = if base < 0 {
    @bidi.process(text)
  } else {
    @bidi.process(
      text,
      direction=if base % 2 == 0 { @bidi.LTR } else { @bidi.RTL },
    )
  }
  let chars = paragraph.chars
  let offsets : Array[Int] = []
  let mut offset = 0
  for ch in chars {
    offsets.push(offset)
    offset += if ch.to_int() > 0xffff { 2 } else { 1 }
  }
  offsets.push(offset)
  let clusters = Array::make(text.length(), 0)
  for (start, end) in @linebreak.grapheme_indices_uax29(text) {
    for index in start..<end {
      clusters[index] = start
    }
  }
  let runs : Array[Run] = []
  let char_runs : Array[Int] = []
  let diagnostics : Array[GlyphDiagnostic] = []
  let mut inherited = @common.Script::from_string("Latn")
  for i, ch in chars {
    let script = @unicode.script(ch.to_uint())
    let tag = script.to_iso15924_tag().to_string()
    let script = if tag == "Zyyy" || tag == "Zinh" {
      inherited
    } else {
      inherited = script
      script
    }
    let font = for step in 0..<self.fonts.length() {
      let index = if step == 0 {
        primary
      } else if step <= primary {
        step - 1
      } else {
        step
      }
      let face = self.fonts[index]
      match face.font.glyph_for_codepoint(ch.to_uint()) {
        Ok(Some(glyph)) if glyph != 0U => break index
        Err(_) =>
          @failure.reject("malformed-font", "Font character mapping failed")
        _ => ()
      }
    } nobreak {
      diagnostics.push({
        code: "missing-glyph",
        cluster: offsets[i],
        codepoint: ch.to_int(),
      })
      0
    }
    if ch.to_int() >= 0x1f000 ||
      ch.to_int() == 0x200d ||
      (ch.to_int() >= 0xfe00 && ch.to_int() <= 0xfe0f) {
      diagnostics.push({
        code: "unsupported-emoji",
        cluster: offsets[i],
        codepoint: ch.to_int(),
      })
    }
    let level = paragraph.levels[i]
    if runs.last() is Some(run) &&
      run.font == font &&
      run.level == level &&
      run.script.to_tag() == script.to_tag() {
      runs[runs.length() - 1] = { ..run, end: i + 1, }
    } else {
      runs.push({ start: i, end: i + 1, font, level, script, })
    }
    char_runs.push(runs.length() - 1)
  }
  let visual : Array[Int] = []
  for i in @bidi.reorder(paragraph) {
    let index = char_runs[i]
    if visual.last() != Some(index) {
      visual.push(index)
    }
  }
  let glyphs : Array[Glyph] = []
  let outlines : Array[Outline] = []
  let run_views : Array[GlyphRun] = []
  let mut x = 0.0
  for index in visual {
    let run = runs[index]
    let face = self.fonts[run.font]
    let ratio = size / face.upem.to_double()
    let buffer = @buffer.Buffer::new()
    for i in run.start..<run.end {
      buffer.add_char(
        @bidi.get_mirrored(chars[i], run.level),
        cluster=clusters[offsets[i]].max(offsets[run.start]),
      )
    }
    buffer.set_direction(
      if run.level % 2 == 1 {
        @common.direction_rtl
      } else {
        @common.direction_ltr
      },
    )
    buffer.set_script(run.script)
    buffer.set_language(@common.Language::from_string(language))
    match @shaper.shape(face.font, buffer) {
      Err(error) =>
        @failure.reject("shaping-failed", "OpenType shaping failed: \{error}")
      Ok(_) => ()
    }
    run_views.push({
      start: offsets[run.start],
      end: offsets[run.end],
      level: run.level,
      font: run.font,
      script: run.script.to_iso15924_tag().to_string(),
      language,
    })
    // The MoonBit shaper returns logical order; emit horizontal RTL in visual order.
    for visual_index in 0..<buffer.len() {
      let i = if run.level % 2 == 1 {
        buffer.len() - visual_index - 1
      } else {
        visual_index
      }
      let info = buffer.infos()[i]
      let position = buffer.positions()[i]
      let (key, path, fresh) = self.outline(run.font, info.codepoint)
      if fresh {
        inserted.push(key)
        outlines.push({ key, path, })
      }
      glyphs.push({
        id: info.codepoint,
        cluster: info.cluster,
        font: run.font,
        outline: key,
        x: x + position.x_offset.to_double() * ratio,
        y: -position.y_offset.to_double() * ratio,
        scale: ratio,
        advance: position.x_advance,
        yAdvance: position.y_advance,
        xOffset: position.x_offset,
        yOffset: position.y_offset,
      })
      x += position.x_advance.to_double() * ratio
    }
  }
  let fonts = self.font_info()
  {
    text,
    glyphs,
    outlines,
    runs: run_views,
    fonts,
    diagnostics,
    width: x,
    fontBytes: self.font_bytes,
    outlineBytes: self.outline_bytes,
  }
}
