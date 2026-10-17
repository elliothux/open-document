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
}

///|
pub(all) struct PathStyle {
  fillAlpha : Double
  strokeAlpha : Double
  dash : Array[Double]
  cap : Int
  join : Int
  miter : Double
}

///|
pub fn PathStyle::validate(self : PathStyle) -> Unit raise @failure.Failure {
  guard self.fillAlpha >= 0 &&
    self.fillAlpha <= 1 &&
    self.strokeAlpha >= 0 &&
    self.strokeAlpha <= 1 &&
    self.dash.length() <= 256 &&
    self.dash.all(v => v >= 0 && v <= 1000000000) &&
    (self.dash.is_empty() || self.dash.any(v => v > 0)) &&
    self.cap >= 0 &&
    self.cap <= 2 &&
    self.join >= 0 &&
    self.join <= 2 &&
    self.miter >= 1 &&
    self.miter <= 1000 else {
    @failure.reject("invalid-drawing", "Invalid positioned path style")
  }
}

///|
pub(all) enum PositionedPrimitive {
  Rectangle(Fill)
  GradientRectangle(Border, String, String)
  Stroke(Border, String, Double)
  Text(PositionedText)
  Image(PlacedImage, Double)
  Path(Array[PathSegment], String, String, Double, PathStyle)
  Transform(Matrix)
  Clip(Border)
  ClipPath(Array[PathSegment], Bool)
  Restore
}

///|
pub(all) struct PositionedPage {
  width : Double
  height : Double
  primitives : Array[PositionedPrimitive]
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
    pages: self.pages.mapi((index, page) => {
      let primitives : Array[PositionedPrimitive] = []
      for fill in page.fills {
        primitives.push(Rectangle(fill))
      }
      for border in page.borders {
        primitives.push(Stroke(border.rect, border.color, border.width))
      }
      for line in page.lines + self.running[index] {
        if line.cellClip is Some(rect) {
          primitives.push(Clip(rect))
        }
        primitives.append(line.positioned(self.fonts, page.width))
        if line.cellClip is Some(_) {
          primitives.push(Restore)
        }
      }
      for border in page.pageBorders {
        primitives.push(Rectangle(border))
      }
      { width: page.width, height: page.height, primitives, }
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
    for primitive in page.primitives {
      match primitive {
        Rectangle(fill) => commands.push(FillRect(fill))
        GradientRectangle(rect, start, end) => {
          validate_gradient(rect, start, end)
          commands.push(GradientRect(rect, start, end))
        }
        Stroke(rect, color, width) =>
          commands.push(StrokeRect(rect, color, width))
        Image(image, opacity) => {
          guard !opacity.is_nan() &&
            !opacity.is_inf() &&
            opacity >= 0 &&
            opacity <= 1 else {
            @failure.reject(
              "invalid-drawing", "Invalid positioned image opacity",
            )
          }
          if opacity != 1 {
            commands.push(
              Style({ ..DrawStyle::default(), fillAlpha: opacity, }),
            )
          }
          commands.push(
            Image({ ..image, key: images.get(image.key).identity, }),
          )
          if opacity != 1 {
            commands.push(Style(DrawStyle::default()))
          }
        }
        Path(path, fill, stroke, width, pen) => {
          pen.validate()
          commands.push(
            Style({
              ..DrawStyle::default(),
              fillAlpha: pen.fillAlpha,
              strokeAlpha: pen.strokeAlpha,
              dash: pen.dash,
              cap: pen.cap,
              join: pen.join,
              miter: pen.miter,
            }),
          )
          commands.push(Path(path, fill, stroke, width))
          commands.push(Style(DrawStyle::default()))
        }
        Transform(matrix) => commands.push(Transform(matrix))
        Clip(rect) => commands.push(ClipRect(rect))
        ClipPath(path, even_odd) => commands.push(ClipPath(path, even_odd))
        Restore => commands.push(Restore)
        Text(text) =>
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
      }
    }
    commands.push(Restore)
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
  // shortcut: Text blocks carry only text; add effect primitives when XLSX/PPTX expose them.
  guard !style.underline && !style.strike && style.highlight.is_empty() else {
    @failure.reject(
      "unsupported-text", "Text block decorations require positioned primitives",
    )
  }
  guard text.length() <= 32767 && width > 0 && width <= 14400 else {
    @failure.reject("limit-exceeded", "Cell text layout exceeds budget")
  }
  let paragraph : Paragraph = {
    id: 0,
    container: 0,
    nominalSize: style.size,
    defaultTab: 36,
    tabs: [],
    decimalSymbol: ".",
    expandSoftBreak: true,
    spans: [{ node: 0, text, style, image: None, field: "", }],
    before: 0,
    after: 0,
    line: Auto(240),
    left: 0,
    right: 0,
    first: 0,
    align: "left",
    pageBreakBefore: false,
    keepLines: false,
    keepNext: false,
    widowControl: false,
    rtl: false,
    marker: None,
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
      text: line.markerText + line.text,
      runs: line
      .paint_runs()
      .map(run => {
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

///|
/// Paint one laid-out line, including its decorations and clipping.
pub fn Line::positioned(
  self : Line,
  fonts : Array[FontInfo],
  width : Double,
) -> Array[PositionedPrimitive] {
  let line = self
  let primitives : Array[PositionedPrimitive] = []
  if line.clip {
    primitives.push(Clip({ x: 0, y: line.y, width, height: line.height, }))
  }
  for image in line.images {
    let crop = image.crop
    let width = image.width / (1 - crop[0] - crop[2])
    let height = image.height / (1 - crop[1] - crop[3])
    primitives.push(
      Clip({ x: image.x, y: image.y, width: image.width, height: image.height, }),
    )
    primitives.push(
      Image(
        {
          key: image.key,
          x: image.x - crop[0] * width,
          y: image.y - crop[1] * height,
          width,
          height,
        },
        1,
      ),
    )
    primitives.push(Restore)
  }
  for x in line.bars {
    primitives.push(
      Rectangle({
        x: x - 0.25,
        y: line.y,
        width: 0.5,
        height: line.height,
        color: "000000",
      }),
    )
  }
  for run in line.paint_runs() {
    for decoration in run.decorations {
      if !decoration.highlight.is_empty() {
        primitives.push(
          Rectangle({
            x: run.x + decoration.x,
            y: line.y,
            width: decoration.width,
            height: line.height,
            color: decoration.highlight,
          }),
        )
      }
    }
  }
  primitives.push(
    Text({
      text: line.markerText + line.text,
      runs: line
      .paint_runs()
      .map(run => {
        color: run.color,
        text: run.text,
        glyphs: run.glyphs,
        x: run.x,
        baseline: run.baseline,
      }),
    }),
  )
  let mut descent = 0.0
  for run in line.paint_runs() {
    for range in run.bidi {
      let font = fonts[range.font]
      descent = descent.max(
        scaled_line_metrics(
          font.ascent,
          font.descent,
          font.upem,
          run.nominalSize,
        ).1,
      )
    }
  }
  for run in line.paint_runs() {
    let thickness = run.nominalSize / 18
    let baseline = run.baseline + run.rise
    for decoration in run.decorations {
      for
        (enabled, y) in [
          (decoration.underline, baseline + descent * 0.4 - run.rise.min(0)),
          (decoration.strike, run.baseline - run.size * 0.27),
        ] {
        if enabled {
          primitives.push(
            Rectangle({
              x: run.x + decoration.x,
              y: y - thickness / 2,
              width: decoration.width,
              height: thickness,
              color: run.color,
            }),
          )
        }
      }
    }
  }
  if line.clip {
    primitives.push(Restore)
  }

  primitives
}
