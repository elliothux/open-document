///|
pub(all) struct DrawGlyph {
  outline : String
  upem : Int32
  // Native vector outlines can lack an SFNT font's global bounds.
  fontBounds : (Int32, Int32, Int32, Int32)?
  strokeWidth : Double
  x : Double
  y : Double
  scaleX : Double
  scaleY : Double
}

///|
fn draw_glyph_runs(glyphs : Array[DrawGlyph]) -> Array[Json] {
  let runs = []
  let mut start = 0
  while start < glyphs.length() {
    let first = glyphs[start]
    let positions = [(first.outline, first.x, first.y)]
    let mut end = start + 1
    while end < glyphs.length() {
      let glyph = glyphs[end]
      if glyph.upem != first.upem ||
        glyph.fontBounds != first.fontBounds ||
        glyph.strokeWidth != first.strokeWidth ||
        glyph.scaleX != first.scaleX ||
        glyph.scaleY != first.scaleY {
        break
      }
      positions.push((glyph.outline, glyph.x, glyph.y))
      end += 1
    }
    let bounds = match first.fontBounds {
      Some(bounds) => ToJson::to_json(bounds)
      None => Json::null()
    }
    runs.push(
      ToJson::to_json(
        (
          first.upem,
          bounds,
          first.strokeWidth,
          first.scaleX,
          first.scaleY,
          positions,
        ),
      ),
    )
    start = end
  }
  runs
}

///|
#derive(Eq)
pub(all) enum DrawBlend {
  Normal
  Multiply
  Difference
}

///|
pub extend DrawBlend with Eq::{equal, not_equal}

///|
pub impl ToJson for DrawBlend with fn to_json(self) {
  Json(
    match self {
      Normal => "normal"
      Multiply => "multiply"
      Difference => "difference"
    },
  )
}

///|
pub extend DrawBlend with ToJson::{to_json}

///|
#derive(Eq, ToJson)
pub(all) struct DrawStyle {
  fillAlpha : Double
  strokeAlpha : Double
  evenOdd : Bool
  cap : Int32
  join : Int32
  miter : Double
  dash : Array[Double]
  dashOffset : Double
  blend : DrawBlend
}

///|
pub extend DrawStyle with ToJson::{to_json}

///|
pub extend DrawStyle with Eq::{equal, not_equal}

///|
pub fn DrawStyle::default() -> DrawStyle {
  {
    fillAlpha: 1,
    strokeAlpha: 1,
    evenOdd: false,
    cap: 0,
    join: 0,
    miter: 10,
    dash: [],
    dashOffset: 0,
    blend: Normal,
  }
}

///|
#derive(ToJson)
pub(all) struct AxialClip {
  transforms : Array[Matrix]
  startX : Double
  endX : Double
  y : Double
  startBounded : Bool
  endBounded : Bool
}

///|
pub extend AxialClip with ToJson::{to_json}

///|
#derive(ToJson)
pub(all) struct GradientClip {
  axial : AxialClip?
}

///|
pub extend GradientClip with ToJson::{to_json}

///|
pub const TileReplayWork : Int32 = 1048576

///|
pub(all) enum DrawCommand {
  FillRect(Fill, screen_fractional~ : Bool)
  GradientRect(Border, Array[GradientStop])
  RadialGradientRect(Border, Array[GradientStop])
  PatternRect(Border, Double, Bytes, String, String, screen_device~ : Bool)
  StrokeRect(Border, String, Double, screen_fractional~ : Bool)
  Glyphs(Double, Double, String, Array[DrawGlyph])
  Image(PlacedImage, crop~ : (Border, Border)?, preserve_pixels~ : Bool)
  Path(Array[PathSegment], String, String, Double)
  OutlinedPath(Array[PathSegment], String, String, Double, Array[PathSegment])
  FilledOutline(Array[PathSegment], String, String, Double, Array[PathSegment])
  DashedPath(
    Array[PathSegment],
    String,
    String,
    Double,
    Array[Array[(Double, Double)]],
  )
  RectangleDashedPath(
    Array[PathSegment],
    String,
    String,
    Double,
    Array[(Int32, Double, Double, Double, Bool)],
  )
  TextRule(Array[PathSegment], String, Double)
  Transform(Matrix)
  ClipRect(Border)
  GradientClipRect(Border, GradientClip)
  Style(DrawStyle)
  PixelCenters
  IntegerScreenGlyphs
  ClipPath(Array[PathSegment], Bool)
  GradientClipPath(Array[PathSegment], Bool, GradientClip)
  Restore
  Layer(Double, Array[DrawCommand])
  Mask(Array[DrawCommand], Array[DrawCommand])
  Tile(Double, Double, Int32, Int32, Matrix, Double, Double, Array[DrawCommand])
  CachedDrawing(String, Json)
}

///|
pub impl ToJson for DrawCommand with fn to_json(self) {
  match self {
    FillRect(rect, screen_fractional~) =>
      if screen_fractional {
        { "op": "fillRect", "rect": rect, "screenFractional": true }
      } else {
        { "op": "fillRect", "rect": rect }
      }
    GradientRect(rect, stops) =>
      {
        "op": "gradientRect",
        "rect": rect,
        "stops": drawing_gradient_stops(stops),
      }
    RadialGradientRect(rect, stops) => {
      let x = rect.x + rect.width / 2
      let y = rect.y + rect.height / 2
      {
        "op": "radialGradientRect",
        "rect": rect,
        "stops": drawing_gradient_stops(stops),
        "circles": [
          x,
          y,
          RADIAL_GRADIENT_INNER_RADIUS,
          x,
          y,
          rect.width.max(rect.height) / 2,
        ],
      }
    }
    PatternRect(rect, period, mask, zero, one, screen_device~) =>
      {
        "op": "patternRect",
        "rect": rect,
        "period": period,
        "mask": mask.iter().map(byte => byte.to_int()).collect(),
        "zero": zero,
        "one": one,
        "screenDevice": screen_device,
      }
    StrokeRect(rect, color, width, screen_fractional~) => {
      let command = {
        "op": Json("strokeRect"),
        "rect": rect.to_json(),
        "color": Json(color),
        "lineWidth": Json(width),
      }
      if screen_fractional {
        command["screenFractional"] = Json(true)
      }
      Json::object(command)
    }
    Glyphs(x, y, color, glyphs) =>
      {
        "op": "glyphs",
        "x": x,
        "y": y,
        "color": color,
        "runs": draw_glyph_runs(glyphs),
      }
    Image(image, crop~, preserve_pixels~) => {
      let command = { "op": Json("image"), "image": image.to_json() }
      if preserve_pixels && image.interpolate is None {
        command["preservePixels"] = Json(true)
      }
      if crop is Some((clip, visible)) {
        command["crop"] = { "clip": clip, "visible": visible }
      }
      Json::object(command)
    }
    Path(path, fill, stroke, width) =>
      path_command_json(path, fill, stroke, width)
    OutlinedPath(path, fill, stroke, width, outline) =>
      path_command_json(path, fill, stroke, width, outline=Some(outline))
    FilledOutline(_, fill, _, _, outline) =>
      path_command_json(outline, fill, "", 0)
    DashedPath(path, fill, stroke, width, pieces) =>
      path_command_json(path, fill, stroke, width, dashes=Some(pieces))
    RectangleDashedPath(path, fill, stroke, width, spans) =>
      path_command_json(path, fill, stroke, width, rectangle_dashes=Some(spans))
    TextRule(path, color, width) =>
      path_command_json(path, "", color, width, text_rule=true)
    Transform(matrix) => { "op": "transform", "matrix": matrix }
    ClipRect(rect) => { "op": "clipRect", "rect": rect }
    GradientClipRect(rect, shading) =>
      { "op": "clipRect", "rect": rect, "shading": shading }
    Style(style) => { "op": "style", "style": style }
    PixelCenters => { "op": "pixelCenters" }
    IntegerScreenGlyphs => { "op": "integerScreenGlyphs" }
    ClipPath(path, even_odd) => clip_path_json(path, even_odd, None)
    GradientClipPath(path, even_odd, shading) =>
      clip_path_json(path, even_odd, Some(shading))
    Restore => { "op": "restore" }
    Layer(opacity, commands) =>
      { "op": "layer", "opacity": opacity, "commands": commands }
    Mask(mask, commands) => { "op": "mask", "mask": mask, "commands": commands }
    Tile(width, height, columns, rows, matrix, x, y, commands) => {
      let tile : Json = {
        "op": "tile",
        "width": width,
        "height": height,
        "columns": columns,
        "rows": rows,
        "matrix": matrix,
        "resolution": { "x": x, "y": y },
        "commands": commands,
      }
      if tile is Object(fields) &&
        columns.to_int64() * rows.to_int64() * commands.length().to_int64() <=
        TileReplayWork.to_int64() {
        fields["replay"] = true
      }
      tile
    }
    CachedDrawing(key, commands) =>
      { "op": "chartTile", "key": key, "commands": commands }
  }
}

///|
pub extend DrawCommand with ToJson::{to_json}

///|
fn path_command_json(
  path : Array[PathSegment],
  fill : String,
  stroke : String,
  width : Double,
  text_rule~ : Bool = false,
  outline~ : Array[PathSegment]? = None,
  dashes~ : Array[Array[(Double, Double)]]? = None,
  rectangle_dashes~ : Array[(Int32, Double, Double, Double, Bool)]? = None,
) -> Json {
  let fields = {
    "op": Json("path"),
    "path": ToJson::to_json(path),
    "fill": Json(fill),
    "stroke": Json(stroke),
    "lineWidth": Json(width),
  }
  if text_rule {
    fields["textRule"] = Json(true)
  }
  if outline is Some(outline) {
    fields["strokeOutline"] = Json(outline)
    if !fill.is_empty() && linear_bounds(path) is Some(bounds) {
      fields["strokeBounds"] = Json(bounds)
    }
  }
  if dashes is Some(pieces) {
    fields["strokeDashes"] = Json(pieces)
    fields["strokeDashesAxisAligned"] = Json(
      pieces.all(points => {
        for i in 1..<points.length() {
          let (ax, ay) = points[i - 1]
          let (bx, by) = points[i]
          if ax != bx && ay != by {
            break false
          }
        } nobreak {
          true
        }
      }),
    )
  }
  if rectangle_dashes is Some(spans) {
    fields["rectangleDashes"] = Json(spans)
  }
  if !stroke.is_empty() {
    let (geometry, non_rectangular) = stroke_geometry(path)
    if geometry is Some(geometry) {
      fields["strokeGeometry"] = Json(geometry)
    }
    if non_rectangular {
      fields["strokeNonRectangular"] = Json(true)
    }
  }
  Json::object(fields)
}

///|
fn clip_path_json(
  path : Array[PathSegment],
  even_odd : Bool,
  shading : GradientClip?,
) -> Json {
  let fields = { "op": Json("clipPath"), "evenOdd": Json(even_odd) }
  if clip_rectangle(path[:]) is Some(rectangle) {
    fields["rectangle"] = Json(rectangle)
  } else {
    fields["path"] = ToJson::to_json(path)
  }
  if shading is Some(shading) {
    fields["shading"] = Json(shading)
  }
  Json::object(fields)
}

///|
pub(all) enum StrokeRaster {
  IntegerStroke
  FractionalStroke
  CoverageStroke
}

///|
pub(all) enum GlyphRaster {
  IntegerGlyphs
  FractionalGlyphs
  CoverageGlyphs
}

///|
pub(all) struct DrawingRegion {
  width : Double
  height : Double
  strokeRaster : StrokeRaster
  glyphRaster : GlyphRaster
  commands : Array[DrawCommand]
}

///|
/// Keep the region header shared by standard and compact drawing encoders.
pub fn DrawingRegion::encode(self : DrawingRegion, commands : Json) -> Json {
  let fields = {
    "width": Json(self.width),
    "height": Json(self.height),
    "commands": commands,
  }
  if self.commands.get(0) is Some(ClipRect(rect) | GradientClipRect(rect, _)) &&
    rect.x == 0 &&
    rect.y == 0 &&
    rect.width == self.width &&
    rect.height == self.height {
    fields["backingClip"] = Json(true)
    if self.strokeRaster is CoverageStroke {
      fields["deviceClips"] = Json(true)
    }
  }
  match self.strokeRaster {
    IntegerStroke => ()
    FractionalStroke => fields["strokeRaster"] = Json("fractional")
    CoverageStroke => {
      fields["imageSampling"] = Json("coverage")
      fields["strokeRaster"] = Json("coverage")
    }
  }
  match self.glyphRaster {
    IntegerGlyphs => ()
    FractionalGlyphs => fields["glyphRaster"] = Json("fractional")
    CoverageGlyphs => fields["glyphRaster"] = Json("coverage")
  }
  Json::object(fields)
}

///|
pub impl ToJson for DrawingRegion with fn to_json(self) {
  self.encode(Json(self.commands))
}

///|
pub extend DrawingRegion with ToJson::{to_json}

///|
// Reading order and text bounds are independent of the drawing commands.
#derive(ToJson)
pub(all) struct SemanticLine {
  paragraph : Int32
  container : Int32
  baseLevel : Int32
  text : String
  marker : String?
  start : Int32
  end : Int32
  x : Double
  areaX : Double
  areaWidth : Double
  y : Double
  width : Double
  height : Double
  readOnlyReason : String
}

///|
#derive(ToJson)
pub(all) struct SemanticPage {
  lines : Array[SemanticLine]
}

///|
pub extend SemanticLine with ToJson::{to_json}

///|
pub extend SemanticPage with ToJson::{to_json}

///|
/// Produce platform-independent commands in point coordinates, in paint order.
pub fn Layout::drawing(
  self : Layout,
  images : Images,
) -> Array[DrawingRegion] raise @failure.Failure {
  self.positioned().drawing(images)
}

///|
pub fn Layout::semantics(self : Layout) -> Array[SemanticPage] {
  let detached : Map[Int32, Array[PlacedDrawingFrame]] = Map([])
  for page in self.pages {
    for line in page.lines {
      if line.caretOnly && !line.drawings.is_empty() {
        let drawings = detached.get_or_init(line.paragraph, () => [])
        drawings.append(line.drawings)
      }
    }
  }
  self.pages.mapi((index, page) => {
    let lines : Array[SemanticLine] = []
    let source_lines = self.running[index].lines.filter(line => {
        line.container == -1
      }) +
      page.lines +
      self.running[index].lines.filter(line => line.container == -3) +
      self.running[index].lines.filter(line => line.container == -2)
    let text_drawings = text_box_reading_order(
      source_lines.map(line => line.drawings).flatten(),
    )
    let mut drawing_index = 0
    for line in source_lines {
      if !line.caretOnly {
        // Wrapping detaches drawings for painting; keep their text at the source marker.
        let drawings = detached
          .get(line.paragraph)
          .unwrap_or([])
          .filter(image => image.start >= line.start && image.start < line.end)
        lines.push({ ..line, drawings: line.drawings + drawings, }.semantic())
      }
      for _ in line.drawings {
        let image = text_drawings[drawing_index]
        drawing_index += 1
        if image.content is TextBox(_, text) {
          for nested in text.lines {
            let semantic = nested.semantic()
            lines.push({
              ..semantic,
              paragraph: if [-1, -2].contains(line.container) {
                line.paragraph
              } else {
                semantic.paragraph
              },
              container: if [-1, -2].contains(line.container) {
                line.container
              } else {
                semantic.container
              },
              readOnlyReason: if [-1, -2].contains(line.container) {
                line.readOnlyReason
              } else {
                semantic.readOnlyReason
              },
              x: semantic.x + image.x,
              areaX: semantic.areaX + image.x,
              y: semantic.y + image.y,
            })
          }
        }
      }
    }
    { lines, }
  })
}

///|
fn Line::semantic(line : Line) -> SemanticLine {
  {
    paragraph: line.paragraph,
    container: line.container,
    baseLevel: line.baseLevel,
    text: line.display_text(),
    marker: if line.markerText.is_empty() {
      None
    } else {
      Some(line.markerText)
    },
    start: line.start,
    end: line.end,
    x: line.x,
    areaX: line.areaX,
    areaWidth: line.areaWidth,
    y: line.y,
    width: line.width,
    height: line.height,
    readOnlyReason: line.readOnlyReason,
  }
}

///|
pub fn Layout::drawing_images(
  self : Layout,
  images : Images,
) -> Array[String] raise @failure.Failure {
  let keys : Map[String, Unit] = Map([])
  for page in self.pages {
    for line in page.lines {
      for image in line.drawings {
        if image.content is Picture(key, _) {
          keys[images.get(key).identity] = ()
        }
      }
    }
  }
  keys.keys().collect()
}
