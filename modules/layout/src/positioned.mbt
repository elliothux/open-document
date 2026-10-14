///|
pub(all) struct PositionedRun {
  color : String
  text : String
  glyphs : Array[Glyph]
  x : Double
  baseline : Double
}

///|
pub(all) struct PositionedText {
  text : String
  runs : Array[PositionedRun]
  clip : Border?
  images : Array[PlacedImage]
}

///|
pub(all) struct PositionedStroke {
  rect : Border
  color : String
  width : Double
}

///|
pub(all) struct PositionedPage {
  width : Double
  height : Double
  texts : Array[PositionedText]
  fills : Array[Fill]
  strokes : Array[PositionedStroke]
}

///|
pub(all) struct PositionedDocument {
  pages : Array[PositionedPage]
  fonts : Array[FontInfo]
}

///|
pub fn Layout::positioned(self : Layout) -> PositionedDocument {
  {
    fonts: self.fonts,
    pages: self.pages.map(page => {
      width: page.width,
      height: page.height,
      fills: page.fills,
      strokes: page.borders.map(rect => { rect, color: "000000", width: 0.5, }),
      texts: page.lines.map(line => {
        text: line.text,
        images: line.images,
        clip: if line.clip {
          Some({ x: 0, y: line.y, width: page.width, height: line.height, })
        } else {
          None
        },
        runs: line.runs.map(run => {
          color: run.color,
          text: run.text,
          glyphs: run.glyphs,
          x: run.x,
          baseline: run.baseline,
        }),
      }),
    }),
  }
}

///|
pub fn PositionedDocument::drawing(
  self : PositionedDocument,
  images : Images,
) -> Array[DrawingRegion] raise @failure.Failure {
  self.pages.map(page => {
    let commands : Array[DrawCommand] = [
      ClipRect({ x: 0, y: 0, width: page.width, height: page.height, }),
      FillRect({
        x: 0,
        y: 0,
        width: page.width,
        height: page.height,
        color: "ffffff",
      }),
    ]
    for fill in page.fills {
      commands.push(FillRect(fill))
    }
    for stroke in page.strokes {
      commands.push(StrokeRect(stroke.rect, stroke.color, stroke.width))
    }
    for text in page.texts {
      if text.clip is Some(rect) {
        commands.push(ClipRect(rect))
      }
      for image in text.images {
        commands.push(Image({ ..image, key: images.get(image.key).identity, }))
      }
      for run in text.runs {
        commands.push(
          Glyphs(
            run.x,
            run.baseline,
            run.color,
            run.glyphs.map(glyph => {
              outline: glyph.outline,
              x: glyph.x,
              y: glyph.y,
              scaleX: glyph.scale,
              scaleY: -glyph.scale,
            }),
          ),
        )
      }
      if text.clip is Some(_) {
        commands.push(RestoreClip)
      }
    }
    commands.push(RestoreClip)
    { width: page.width, height: page.height, commands, }
  })
}

///|
pub(all) struct TextBlock {
  texts : Array[PositionedText]
  widths : Array[Double]
  height : Double
}

///|
/// Resolve text with the same shaping, fallback and line breaking as document text.
pub fn TextProbe::text_block(
  self : TextProbe,
  text : String,
  style : TextStyle,
  profile : Map[String, String],
  width : Double,
  wrap : Bool,
) -> TextBlock raise @failure.Failure {
  self.check()
  guard text.length() <= 32767 && width > 0 && width <= 14400 else {
    @failure.reject("limit-exceeded", "Cell text layout exceeds budget")
  }
  let paragraph : Paragraph = {
    id: 0,
    container: 0,
    nominalSize: style.size,
    spans: [{ node: 0, text, style, image: None, }],
    before: 0,
    after: 0,
    line: Auto(240),
    left: 0,
    right: 0,
    first: 0,
    align: "left",
    pageBreakBefore: false,
    readOnlyReason: "",
  }
  let cache = ParagraphCache::new(self, profile)
  let available = if wrap { width } else { 1000000000.0 }
  let measured = cache.lines(self, paragraph, profile, available) catch {
    Failure(code="layout-overflow", ..) =>
      cache.lines(self, paragraph, profile, 1000000000.0)
    error => raise error
  }
  // Retain only the existing bounded text cache; old viewport entries may be evicted.
  if self.paragraphs.length() >= 1024 {
    self.paragraphs.clear()
    self.text_units = 0
  }
  for key, lines in cache.current {
    if !self.paragraphs.contains(key) {
      let units = paragraph_cache_units(key, lines.map(item => item.line))
      if units <= 1048576 - self.text_units {
        self.paragraphs[key] = lines
        self.text_units += units
      }
    }
  }
  let texts : Array[PositionedText] = []
  let widths : Array[Double] = []
  let mut y = 0.0
  for item in measured {
    let line = item.line
    texts.push({
      text: line.text,
      clip: None,
      images: [],
      runs: line.runs.map(run => {
        color: run.color,
        text: run.text,
        glyphs: run.glyphs,
        x: run.x,
        baseline: run.baseline + y,
      }),
    })
    widths.push(line.width)
    y += line.height
  }
  { texts, widths, height: y, }
}
