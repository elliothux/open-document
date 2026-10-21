///|
pub(all) struct DrawGlyph {
  outline : String
  x : Double
  y : Double
  scaleX : Double
  scaleY : Double
} derive(ToJson)

///|
pub extend DrawGlyph with ToJson::{to_json}

///|
pub(all) struct DrawStyle {
  fillAlpha : Double
  strokeAlpha : Double
  evenOdd : Bool
  cap : Int
  join : Int
  miter : Double
  dash : Array[Double]
  dashOffset : Double
  multiply : Bool
  imageSmoothing : Bool
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
    multiply: false,
    imageSmoothing: true,
  }
}

///|
pub(all) enum DrawCommand {
  FillRect(Fill)
  GradientRect(Border, Array[GradientStop])
  StrokeRect(Border, String, Double)
  Glyphs(Double, Double, String, Array[DrawGlyph])
  Image(PlacedImage)
  Path(Array[PathSegment], String, String, Double)
  Transform(Matrix)
  ClipRect(Border)
  Style(DrawStyle)
  ClipPath(Array[PathSegment], Bool)
  Restore
  Layer(Double, Array[DrawCommand])
}

///|
pub impl ToJson for DrawCommand with fn to_json(self) {
  match self {
    FillRect(rect) => { "op": "fillRect", "rect": rect }
    GradientRect(rect, stops) =>
      { "op": "gradientRect", "rect": rect, "stops": stops }
    StrokeRect(rect, color, width) =>
      { "op": "strokeRect", "rect": rect, "color": color, "lineWidth": width }
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
    Transform(matrix) => { "op": "transform", "matrix": matrix }
    ClipRect(rect) => { "op": "clipRect", "rect": rect }
    Style(style) => { "op": "style", "style": style }
    ClipPath(path, even_odd) =>
      { "op": "clipPath", "path": path, "evenOdd": even_odd }
    Restore => { "op": "restore" }
    Layer(opacity, commands) =>
      { "op": "layer", "opacity": opacity, "commands": commands }
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
  paragraph : Int
  container : Int
  baseLevel : Int
  text : String
  marker : String?
  start : Int
  end : Int
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
  self.pages.mapi((index, page) => {
    let lines : Array[SemanticLine] = []
    for
      line in self.running[index].filter(line => line.container == -1) +
      page.lines +
      self.running[index].filter(line => line.container == -2) {
      if !line.caretOnly {
        lines.push(line.semantic())
      }
      for image in line.drawings {
        if image.content is TextBox(_, text) {
          for nested in text.lines {
            let semantic = nested.semantic()
            lines.push({
              ..semantic,
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
