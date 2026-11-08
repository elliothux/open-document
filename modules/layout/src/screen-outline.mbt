///|
/// Prepare light-hinted outlines in 96 dpi device pixels for a screen run.
pub fn TextProbe::prepare_screen_outlines(
  self : TextProbe,
  glyphs : Array[Glyph],
  logical_size : Int32,
) -> Unit {
  let ppem = logical_size.to_double() * 96 / 2540
  if ppem < 0.5 {
    return
  }
  let fonts : Map[
    Int32,
    (@outline.OutlineGlyphCollection, @outline.HintingInstance)?,
  ] = Map([])
  for glyph in glyphs {
    let key = "\{glyph.outline}:screen:\{logical_size}"
    if glyph.strokeWidth != 0 || self.outlines.contains(key) {
      continue
    }
    let prepared = match fonts.get(glyph.font) {
      Some(prepared) => prepared
      None => {
        let prepared = self.fonts
          .get(glyph.font)
          .bind(font => @moon_skrifa.FontRef::from_bytes(font.bytes))
          .bind(font => {
            let outlines = @outline.OutlineGlyphCollection::from_font(font)
            screen_hints(
              outlines,
              ppem,
              @outline.HintingOptions(
                @outline.Auto(None),
                @outline.Target::Smooth(@outline.Light, true, false),
              ),
            )
          })
        fonts[glyph.font] = prepared
        prepared
      }
    }
    self.cache_screen_outline(glyph, key, prepared)
  }
}

///|
fn screen_hints(
  outlines : @outline.OutlineGlyphCollection,
  ppem : Double,
  options : @outline.HintingOptions,
) -> (@outline.OutlineGlyphCollection, @outline.HintingInstance)? {
  match
    @outline.HintingInstance::create(
      outlines,
      @moon_skrifa.Size(ppem),
      @moon_skrifa.LocationRef::default(),
      options,
    ) {
    Ok(hints) => Some((outlines, hints))
    Err(_) => None
  }
}

///|
fn TextProbe::cache_screen_outline(
  self : TextProbe,
  glyph : Glyph,
  key : String,
  prepared : (@outline.OutlineGlyphCollection, @outline.HintingInstance)?,
  limit~ : Int32 = 8388608,
) -> Unit {
  guard prepared is Some((outlines, hints)) &&
    glyph.id <= 65535U &&
    outlines.get(@moon_skrifa.GlyphId(glyph.id.to_uint16())) is Some(shape) else {
    return
  }
  let pen = @outline.SvgPen::with_precision(6)
  guard shape.draw(@outline.DrawSettings::hinted(hints, false), pen) is Ok(_) else {
    return
  }
  let path = pen.to_string()
  if path.length() <= limit - self.outline_bytes {
    self.outline_bytes += path.length()
    self.outlines[key] = path
  }
}

///|
/// Grid-fit unrotated TrueType chart text without changing shaped origins or advances.
pub fn TextProbe::fit_screen_text(
  self : TextProbe,
  primitives : Array[PositionedPrimitive],
  scale : Double,
) -> Unit {
  guard scale >= 0.25 && scale <= 32 else { return }
  let dpi = (scale * 72).floor()
  let fonts : Map[
    (Int32, Int32),
    (@outline.OutlineGlyphCollection, @outline.HintingInstance)?,
  ] = Map([])
  for index, primitive in primitives {
    guard primitive is Text(text) else { continue }
    let runs = text.runs.map(run => {
      let glyphs = run.glyphs.map(glyph => {
        guard glyph.strokeWidth == 0 && self.fonts.get(glyph.font) is Some(font) else {
          return glyph
        }
        let size = (glyph.scale * font.upem.to_double() * dpi * 64 / 72)
          .round()
          .to_int()
        guard size >= 64 && size <= 16384 else { return glyph }
        let key = "\{glyph.outline}:fit:\{size}"
        // Leave room for the document's source outlines across repeated zooms.
        if !self.outlines.contains(key) && self.outline_bytes < 1048576 {
          let prepared = fonts.get_or_init((glyph.font, size), () => {
            @moon_skrifa.FontRef::from_bytes(font.bytes).bind(font => {
              let outlines = @outline.OutlineGlyphCollection::from_font(font)
              guard outlines.format() is Some(Glyf) else { return None }
              screen_hints(
                outlines,
                size.to_double() / 64,
                @outline.Engine::Interpreter.into(),
              )
            })
          })
          self.cache_screen_outline(glyph, key, prepared, limit=1048576)
        }
        if self.outlines.contains(key) {
          { ..glyph, outline: key, scale: 1 / scale, }
        } else {
          glyph
        }
      })
      { ..run, glyphs, }
    })
    primitives[index] = Text({ ..text, runs, })
  }
}
