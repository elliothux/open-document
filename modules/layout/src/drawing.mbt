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
pub(all) enum DrawCommand {
  FillRect(Fill)
  StrokeRect(Border, String, Double)
  Glyphs(Double, Double, String, Array[DrawGlyph])
  Image(PlacedImage)
  ClipRect(Border)
  RestoreClip
}

///|
pub impl ToJson for DrawCommand with fn to_json(self) {
  match self {
    FillRect(rect) => { "op": "fillRect", "rect": rect }
    StrokeRect(rect, color, width) =>
      { "op": "strokeRect", "rect": rect, "color": color, "lineWidth": width }
    Glyphs(x, y, color, glyphs) =>
      { "op": "glyphs", "x": x, "y": y, "color": color, "glyphs": glyphs }
    Image(image) => { "op": "image", "image": image }
    ClipRect(rect) => { "op": "clipRect", "rect": rect }
    RestoreClip => { "op": "restoreClip" }
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
  self.pages.map(page => {
    lines: page.lines.map(line => {
      paragraph: line.paragraph,
      container: line.container,
      baseLevel: line.baseLevel,
      text: line.text,
      start: line.start,
      end: line.end,
      x: line.x,
      areaX: line.areaX,
      areaWidth: line.areaWidth,
      y: line.y,
      width: line.width,
      height: line.height,
      readOnlyReason: line.readOnlyReason,
    }),
  })
}

///|
pub fn Layout::drawing_images(
  self : Layout,
  images : Images,
) -> Array[String] raise @failure.Failure {
  let keys : Map[String, Unit] = Map([])
  for page in self.pages {
    for line in page.lines {
      for image in line.images {
        keys[images.get(image.key).identity] = ()
      }
    }
  }
  keys.keys().collect()
}
