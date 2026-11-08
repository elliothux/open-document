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
pub impl ToJson for DrawGlyph with fn to_json(self) {
  {
    "outline": self.outline,
    "upem": self.upem,
    "fontBounds": match self.fontBounds {
      Some(bounds) => ToJson::to_json(bounds)
      None => Json::null()
    },
    "strokeWidth": self.strokeWidth,
    "x": self.x,
    "y": self.y,
    "scaleX": self.scaleX,
    "scaleY": self.scaleY,
  }
}

///|
pub extend DrawGlyph with ToJson::{to_json}

///|
pub(all) enum DrawBlend {
  Normal
  Multiply
  Difference
} derive(Eq)

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
} derive(ToJson)

///|
pub extend DrawStyle with ToJson::{to_json}

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
pub(all) enum DrawCommand {
  FillRect(Fill)
  GradientRect(Border, Array[GradientStop])
  RadialGradientRect(Border, Array[GradientStop])
  PatternRect(Border, Double, Bytes, String, String, screen_device~ : Bool)
  StrokeRect(Border, String, Double, screen_fractional~ : Bool)
  Glyphs(Double, Double, String, Array[DrawGlyph])
  Image(PlacedImage)
  Path(Array[PathSegment], String, String, Double)
  TextRule(Array[PathSegment], String, Double)
  Transform(Matrix)
  ClipRect(Border)
  Style(DrawStyle)
  PixelCenters
  IntegerScreenGlyphs
  ClipPath(Array[PathSegment], Bool)
  Restore
  Layer(Double, Array[DrawCommand])
  Mask(Array[DrawCommand], Array[DrawCommand])
  Tile(Double, Double, Int32, Int32, Matrix, Double, Double, Array[DrawCommand])
}

///|
pub impl ToJson for DrawCommand with fn to_json(self) {
  match self {
    FillRect(rect) => { "op": "fillRect", "rect": rect }
    GradientRect(rect, stops) =>
      { "op": "gradientRect", "rect": rect, "stops": stops }
    RadialGradientRect(rect, stops) =>
      { "op": "radialGradientRect", "rect": rect, "stops": stops }
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
      { "op": "glyphs", "x": x, "y": y, "color": color, "glyphs": glyphs }
    Image(image) => { "op": "image", "image": image }
    Path(path, fill, stroke, width) =>
      {
        "op": "path",
        "path": path,
        "fill": fill,
        "stroke": stroke,
        "lineWidth": width,
      }
    TextRule(path, color, width) =>
      {
        "op": "path",
        "path": path,
        "fill": "",
        "stroke": color,
        "lineWidth": width,
        "textRule": true,
      }
    Transform(matrix) => { "op": "transform", "matrix": matrix }
    ClipRect(rect) => { "op": "clipRect", "rect": rect }
    Style(style) => { "op": "style", "style": style }
    PixelCenters => { "op": "pixelCenters" }
    IntegerScreenGlyphs => { "op": "integerScreenGlyphs" }
    ClipPath(path, even_odd) =>
      { "op": "clipPath", "path": path, "evenOdd": even_odd }
    Restore => { "op": "restore" }
    Layer(opacity, commands) =>
      { "op": "layer", "opacity": opacity, "commands": commands }
    Mask(mask, commands) => { "op": "mask", "mask": mask, "commands": commands }
    Tile(width, height, columns, rows, matrix, x, y, commands) =>
      {
        "op": "tile",
        "width": width,
        "height": height,
        "columns": columns,
        "rows": rows,
        "matrix": matrix,
        "resolution": { "x": x, "y": y },
        "commands": commands,
      }
  }
}

///|
pub extend DrawCommand with ToJson::{to_json}

///|
pub(all) struct DrawingRegion {
  width : Double
  height : Double
  commands : Array[DrawCommand]
} derive(ToJson)

///|
pub extend DrawingRegion with ToJson::{to_json}

///|
// Reading order and text bounds are independent of the drawing commands.
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
} derive(ToJson)

///|
pub(all) struct SemanticPage {
  lines : Array[SemanticLine]
} derive(ToJson)

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
