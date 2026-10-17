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
  primary~ : Int = 0,
  base~ : Int = -1,
) -> ShapeBatch raise @failure.Failure {
  self.check()
  guard text.length() <= 4096 else {
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
  self.shape_paragraph(
    text,
    size,
    language,
    primary,
    bidi_controls(paragraph),
    geometry=true,
  )
}

///|
fn TextProbe::shape_paragraph(
  self : TextProbe,
  text : String,
  size : Double,
  language : String,
  primary : Int,
  paragraph : @bidi.BidiParagraph,
  geometry~ : Bool,
  caret_units? : Double,
  spacing~ : Map[Int, Double] = Map([]),
  advances? : (Array[(Double, Double)], Int),
  context? : (Array[Char], Int),
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
  let chars = paragraph.chars
  let (context_chars, context_start) = context.unwrap_or((chars, 0))
  guard context_start >= 0 &&
    context_start <= context_chars.length() &&
    chars.length() <= context_chars.length() - context_start &&
    context_chars.length() <= 4096 else {
    @failure.reject("invalid-operation", "Invalid shaping text context")
  }
  if advances is Some((values, start)) {
    guard start >= 0 &&
      start < values.length() &&
      text.length() < values.length() - start &&
      values.length() <= 4097 else {
      @failure.reject(
        "invalid-operation", "Invalid shaping advance destination",
      )
    }
  }
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
    let font = if bidi_control(ch.to_uint()) {
      primary
    } else {
      for step in 0..<self.fonts.length() {
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
    }
    if @unicode.is_emoji_presentation(ch.to_uint()) ||
      ch.to_int() == 0x200d ||
      @unicode.is_variation_selector(ch.to_uint()) {
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
      run.script.to_tag() == script.to_tag() &&
      !spacing.contains(offsets[i]) {
      runs[runs.length() - 1] = { ..run, end: i + 1, }
    } else {
      runs.push({ start: i, end: i + 1, font, level, script, })
    }
    char_runs.push(runs.length() - 1)
  }
  let visual : Array[Int] = []
  for i in bidi_order(paragraph) {
    let index = char_runs[i]
    if visual.last() != Some(index) {
      visual.push(index)
    }
  }
  let trailing_space : Map[Int, Double] = Map([])
  let glyphs : Array[Glyph] = []
  let outlines : Array[Outline] = []
  let run_views : Array[GlyphRun] = []
  let controls : Array[Caret] = []
  let work = @tables.layout_work_budget()
  let mut x = 0.0
  for index in visual {
    let run = runs[index]
    let face = self.fonts[run.font]
    let ratio = size / face.upem.to_double()
    let buffer = @buffer.Buffer::new()
    guard buffer.set_text_context(
      context_chars[:],
      context_start + run.start,
      context_start + run.end,
    ) else {
      @failure.reject("invalid-operation", "Invalid shaping text context")
    }
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
    // shortcut: disable global fraction substitutions until the pinned shaper supports context masks.
    let features = buffer
      .gsub_features()
      .iter()
      .filter(tag => !["frac", "numr", "dnom"].contains(tag.to_string()))
      .collect()
    buffer.set_gsub_features(features)
    buffer.set_gpos_features(features)
    match @shaper.shape(face.font, buffer, work~) {
      Err(@buffer.Layout(@tables.LimitExceeded)) =>
        @failure.reject(
          "limit-exceeded", "OpenType substitution glyph budget exceeded",
        )
      Err(@buffer.Layout(@tables.WorkLimitExceeded)) =>
        @failure.reject(
          "limit-exceeded", "OpenType lookup work budget exceeded",
        )
      Err(error) =>
        @failure.reject("shaping-failed", "OpenType shaping failed: \{error}")
      Ok(_) => ()
    }
    if geometry {
      run_views.push({
        start: offsets[run.start],
        end: offsets[run.end],
        level: run.level,
        font: run.font,
        script: run.script.to_iso15924_tag().to_string(),
        language,
      })
    }
    let gap = spacing.get(offsets[run.end]).unwrap_or(0)
    let gap = if gap > 0 &&
      buffer
      .positions()
      .iter()
      .fold(init=0, (sum, position) => sum + position.x_advance) >
      0 {
      gap
    } else {
      0.0
    }
    if run.level % 2 == 1 {
      x += gap
    } else if gap > 0 {
      trailing_space[offsets[run.end]] = gap
    }
    // The MoonBit shaper returns logical order; emit horizontal RTL in visual order.
    for visual_index in 0..<buffer.len() {
      let i = if run.level % 2 == 1 {
        buffer.len() - visual_index - 1
      } else {
        visual_index
      }
      let position = buffer.positions()[i]
      let info = buffer.infos()[i]
      guard info.cluster >= 0 && info.cluster < text.length() else {
        @failure.reject("shaping-failed", "Invalid shaping source cluster")
      }
      // Substitution can clear glyph Unicode; source clusters retain control identity.
      let control = bidi_control(text[info.cluster].to_uint())
      let advance = if control {
        0.0
      } else {
        position.x_advance.to_double() * ratio
      }
      if geometry && control {
        for offset in [info.cluster, info.cluster + 1] {
          controls.push({ offset, before: x, after: x, })
        }
      }
      if advances is Some((values, start)) {
        let index = start + info.cluster
        let (width, gap) = values[index]
        values[index] = (width + advance, gap)
      }
      if geometry && !control {
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
      }
      x += advance
    }
    if run.level % 2 == 0 {
      x += gap
    }
    if advances is Some((values, start)) {
      let index = start + offsets[run.end]
      let (width, previous) = values[index]
      values[index] = (width, previous + gap)
    }
  }
  let fonts = if geometry { self.font_info() } else { [] }
  {
    text,
    carets: if geometry {
      self
      .shape_carets(text, glyphs, run_views, controls, caret_units?)
      .map(caret => {
        let gap = trailing_space.get(caret.offset).unwrap_or(0)
        {
          ..caret,
          before: caret.before + gap,
          after: caret.after +
          (if caret.offset == text.length() { gap } else { 0.0 }),
        }
      })
    } else {
      []
    },
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
