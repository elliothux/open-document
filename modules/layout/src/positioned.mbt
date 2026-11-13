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
  evenOdd : Bool
  dash : Array[Double]
  cap : Int32
  join : Int32
  miter : Double
}

///|
pub fn PathStyle::solid() -> PathStyle {
  {
    evenOdd: false,
    fillAlpha: 1,
    strokeAlpha: 1,
    dash: [],
    cap: 0,
    join: 0,
    miter: 10,
  }
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
  GradientRectangle(Border, Array[GradientStop])
  RadialGradientRectangle(Border, Array[GradientStop])
  PatternRectangle(Border, Double, Bytes, String, String, screen_device~ : Bool)
  Stroke(Border, String, Double)
  FractionalScreenStroke(Border, String, Double)
  Text(PositionedText)
  TextRule(Array[PathSegment], String, Double)
  Image(PlacedImage, Double)
  Path(Array[PathSegment], String, String, Double, PathStyle)
  Transform(Matrix)
  Clip(Border)
  ClipPath(Array[PathSegment], Bool)
  PixelCenters
  IntegerScreenGlyphs
  CachedDrawing(String, Json)
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
  links : Array[PageLink]
}

///|
pub fn PositionedDocument::drawing_images(
  self : PositionedDocument,
  images : Images,
) -> Array[String] raise @failure.Failure {
  let keys : Map[String, Unit] = Map([])
  for page in self.pages {
    for primitive in page.primitives {
      if primitive is Image(image, _) {
        keys[images.get(image.key).identity] = ()
      }
    }
  }
  keys.keys().to_array()
}

///|
pub fn Layout::positioned(self : Layout) -> PositionedDocument {
  {
    fonts: self.fonts,
    links: [],
    pages: self.pages.mapi((index, page) => {
      let primitives : Array[PositionedPrimitive] = []
      if self.background.to_lower() != "ffffff" {
        primitives.push(
          Rectangle({
            x: 0,
            y: 0,
            width: page.width,
            height: page.height,
            color: self.background,
          }),
        )
      }
      if self.running.get(index) is Some(running) {
        {
          ..running,
          lines: running.lines.filter(line => line.container != -3),
        }.paint(primitives, self.fonts)
        {
          ..page,
          lines: page.lines + running.lines.filter(line => line.container == -3),
        }.paint(primitives, self.fonts)
      } else {
        page.paint(primitives, self.fonts)
      }
      { width: page.width, height: page.height, primitives, }
    }),
  }
}

///|
fn PageFrame::paint(
  self : PageFrame,
  out : Array[PositionedPrimitive],
  fonts : Array[FontInfo],
) -> Unit {
  let floating = self.floating_images()
  for (_, image) in floating {
    if image.anchor.unwrap().behind {
      image.paint(out, fonts)
    }
  }
  for fill in self.fills {
    out.push(Rectangle(fill))
  }
  for border in self.borders {
    out.push(Stroke(border.rect, border.color, border.width))
  }
  for line in self.lines {
    if line.cellClip is Some(rect) {
      out.push(Clip(rect))
    }
    out.append(line.positioned(fonts, self.width, align_text_rules=true))
    if line.cellClip is Some(_) {
      out.push(Restore)
    }
  }
  for (_, image) in floating {
    if !image.anchor.unwrap().behind {
      image.paint(out, fonts)
    }
  }
  for border in self.pageBorders {
    out.push(Rectangle(border))
  }
}

///|
pub fn PositionedDocument::drawing(
  self : PositionedDocument,
  images : Images,
  clear~ : Bool = true,
  stroke_raster~ : StrokeRaster = IntegerStroke,
  glyph_raster~ : GlyphRaster = IntegerGlyphs,
) -> Array[DrawingRegion] raise @failure.Failure {
  let fractional_screen = stroke_raster is FractionalStroke
  let coverage = stroke_raster is CoverageStroke
  self.pages.map(page => {
    let commands : Array[DrawCommand] = [
      ClipRect({ x: 0, y: 0, width: page.width, height: page.height, }),
    ]
    if clear {
      commands.push(
        FillRect(
          {
            x: 0,
            y: 0,
            width: page.width,
            height: page.height,
            color: "ffffff",
          },
          screen_fractional=fractional_screen,
        ),
      )
    }
    for primitive in page.primitives {
      match primitive {
        Rectangle(fill) =>
          commands.push(FillRect(fill, screen_fractional=fractional_screen))
        GradientRectangle(rect, stops) => {
          validate_gradient(rect, stops)
          commands.push(GradientRect(rect, stops))
        }
        RadialGradientRectangle(rect, stops) => {
          validate_gradient(rect, stops)
          commands.push(RadialGradientRect(rect, stops, circles=None))
        }
        PatternRectangle(rect, period, mask, zero, one, screen_device~) => {
          validate_pattern(rect, period, mask, zero, one)
          commands.push(
            PatternRect(rect, period, mask, zero, one, screen_device~),
          )
        }
        Stroke(rect, color, width) =>
          commands.push(StrokeRect(rect, color, width, screen_fractional=false))
        FractionalScreenStroke(rect, color, width) =>
          commands.push(StrokeRect(rect, color, width, screen_fractional=true))
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
            Image(
              { ..image, key: images.get(image.key).identity, },
              crop=None,
              preserve_pixels=fractional_screen,
            ),
          )
          if opacity != 1 {
            commands.push(Style(DrawStyle::default()))
          }
        }
        Path(path, fill, stroke, width, pen) => {
          pen.validate()
          let style = {
            ..DrawStyle::default(),
            fillAlpha: pen.fillAlpha,
            strokeAlpha: pen.strokeAlpha,
            evenOdd: pen.evenOdd,
            dash: pen.dash,
            cap: pen.cap,
            join: pen.join,
            miter: pen.miter,
          }
          commands.push(Style(style))
          commands.push(
            DrawCommand::Path(path, fill, stroke, width).prepare_fill_outline(
              style,
            ),
          )
          commands.push(Style(DrawStyle::default()))
        }
        TextRule(path, color, width) =>
          commands.push(TextRule(path, color, width))
        Transform(matrix) => commands.push(Transform(matrix))
        Clip(rect) => commands.push(ClipRect(rect))
        ClipPath(path, even_odd) => commands.push(ClipPath(path, even_odd))
        PixelCenters => if !coverage { commands.push(PixelCenters) }
        IntegerScreenGlyphs =>
          if !coverage {
            commands.push(IntegerScreenGlyphs)
          }
        CachedDrawing(key, body) => commands.push(CachedDrawing(key, body))
        Restore => close_drawing_scope(commands)
        Text(text) =>
          for run in text.runs {
            commands.push(
              Glyphs(
                run.x,
                run.baseline,
                run.color,
                run.glyphs.map(glyph => {
                  let font = self.fonts
                    .get(glyph.font)
                    .unwrap_or_else(() => {
                      @failure.reject(
                        "missing-font", "Unknown positioned glyph font",
                      )
                    })
                  guard font.bbox.length() == 4 &&
                    font.bbox[0] >= -65536 &&
                    font.bbox[1] >= -65536 &&
                    font.bbox[2] <= 65536 &&
                    font.bbox[3] <= 65536 &&
                    font.bbox[0] <= font.bbox[2] &&
                    font.bbox[1] <= font.bbox[3] else {
                    @failure.reject(
                      "malformed-font", "Invalid positioned font bounds",
                    )
                  }
                  {
                    outline: glyph.outline,
                    upem: font.upem,
                    fontBounds: Some(
                      (font.bbox[0], font.bbox[1], font.bbox[2], font.bbox[3]),
                    ),
                    strokeWidth: glyph.strokeWidth,
                    x: glyph.x,
                    y: glyph.y,
                    scaleX: glyph.scale,
                    scaleY: -glyph.scale,
                  }
                }),
              ),
            )
          }
      }
    }
    commands.push(Restore)
    if !fractional_screen {
      annotate_gradient_clips(commands, device=coverage)
    }
    {
      width: page.width,
      height: page.height,
      strokeRaster: stroke_raster,
      glyphRaster: if fractional_screen {
        FractionalGlyphs
      } else {
        glyph_raster
      },
      commands,
    }
  })
}

///|
fn close_drawing_scope(commands : Array[DrawCommand]) -> Unit {
  // The outer page clip remains a separate canvas scope.
  let count = commands.length()
  if count >= 3 &&
    commands[count - 2] is ClipRect(clip) &&
    commands[count - 1] is Image(image, crop=None, preserve_pixels~) {
    let x = clip.x.max(image.x)
    let y = clip.y.max(image.y)
    let visible : Border = {
      x,
      y,
      width: (clip.x + clip.width).min(image.x + image.width) - x,
      height: (clip.y + clip.height).min(image.y + image.height) - y,
    }
    commands[count - 2] = Image(
      image,
      crop=Some((clip, visible)),
      preserve_pixels~,
    )
    ignore(commands.pop())
  } else {
    commands.push(Restore)
  }
}

///|
pub(all) struct TextBlock {
  lines : Array[Array[PositionedPrimitive]]
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
  cell~ : Bool = false,
) -> TextBlock raise @failure.Failure {
  self.span_block(
    [{ node: 0, text, style, drawing: None, field: "", }],
    style.size,
    profile,
    width,
    wrap,
    cell~,
  )
}

///|
/// Shape mixed text styles with the same bounded paragraph layout as plain blocks.
/// `justify` expands word gaps on nonfinal lines; line breaking and source text stay intact.
/// `distributed` also expands final lines and centers lines containing a single word.
/// `cell` uses native spreadsheet font metrics; other text keeps paragraph metrics.
pub fn TextProbe::span_block(
  self : TextProbe,
  spans : Array[Span],
  nominal_size : Double,
  profile : Map[String, String],
  width : Double,
  wrap : Bool,
  justify~ : Bool = false,
  distributed~ : Bool = false,
  cell~ : Bool = false,
) -> TextBlock raise @failure.Failure {
  self.check()
  guard spans.all(span => span.drawing is None && span.field.is_empty()) else {
    @failure.reject(
      "unsupported-text", "Text blocks require ordinary text spans",
    )
  }
  let mut units = 0
  for span in spans {
    guard span.text.length() <= 32767 - units else {
      @failure.reject("limit-exceeded", "Cell text layout exceeds budget")
    }
    units += span.text.length()
  }
  guard spans.length() <= 32767 && width > 0 && width <= 14400 else {
    @failure.reject("limit-exceeded", "Cell text layout exceeds budget")
  }
  let paragraph : Paragraph = {
    id: 0,
    container: 0,
    nominalSize: nominal_size,
    frame: None,
    defaultTab: 36,
    tabs: [],
    decimalSymbol: ".",
    expandSoftBreak: true,
    spans,
    before: 0,
    after: 0,
    line: Auto(240),
    lineGrid: None,
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
  let cache = ParagraphCache::new(self, profile, text_block=true)
  let available = if wrap { width } else { 1000000000.0 }
  let measured = cache.lines(self, paragraph, profile, available, cell~) catch {
    Failure(code="layout-overflow", ..) =>
      cache.lines(self, paragraph, profile, 1000000000.0, cell~)
    error => raise error
  }
  self.retain_text_cache(cache)
  let lines : Array[Array[PositionedPrimitive]] = []
  let widths : Array[Double] = []
  let mut y = 0.0
  let fonts = self.font_info()
  for index, item in measured {
    let line = if distributed || (justify && index + 1 < measured.length()) {
      justified_line(item.line, width, wordsOnly=true)
    } else {
      item.line
    }
    let x = if distributed && !line.justified {
      (width - line.width).max(0) / 2
    } else if justify && !line.justified && line.baseLevel % 2 == 1 {
      (width - line.width).max(0)
    } else {
      0.0
    }
    lines.push(
      [
        Transform({ a: 1, b: 0, c: 0, d: 1, e: x, f: y, }),
        ..line.positioned(fonts, width),
        Restore,
      ],
    )
    widths.push(line.width)
    y += line.height
  }
  { lines, widths, height: y, }
}

///|
/// Paint one laid-out line, including its decorations and clipping.
pub fn Line::positioned(
  self : Line,
  fonts : Array[FontInfo],
  width : Double,
  underline_descent? : Double,
  align_text_rules~ : Bool = false,
) -> Array[PositionedPrimitive] {
  let line = self
  let primitives : Array[PositionedPrimitive] = []
  if line.clip {
    primitives.push(Clip({ x: 0, y: line.y, width, height: line.height, }))
  }
  if line.markerImage is Some(image) {
    primitives.push(Image(image, 1))
  }
  for image in line.drawings {
    if image.anchor is None {
      image.paint(primitives, fonts)
    }
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
      text: line.markerText + line.display_text(objects=false),
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
  let descent = underline_descent.unwrap_or_else(() => {
    let mut descent = 0.0
    for run in line.paint_runs() {
      for range in run.bidi {
        let font = fonts[range.font]
        descent = descent.max(
          font.descent.to_double() * run.nominalSize / font.upem.to_double(),
        )
      }
    }
    descent
  })
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
          let path = [
            Move(run.x + decoration.x, y + thickness / 2),
            Line(run.x + decoration.x + decoration.width, y + thickness / 2),
          ]
          primitives.push(
            if align_text_rules {
              TextRule(path, run.color, thickness)
            } else {
              Path(path, "", run.color, thickness, PathStyle::solid())
            },
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
