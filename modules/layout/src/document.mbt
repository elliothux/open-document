///|
pub(all) struct TextStyle {
  font : String
  size : Double
  color : String
} derive(ToJson)

///|
pub extend TextStyle with ToJson::{to_json}

///|
pub(all) struct Span {
  node : Int
  text : String
  style : TextStyle
  image : InlineImage?
}

///|
pub impl ToJson for Span with fn to_json(self) {
  let image : Json = match self.image {
    None => Json::null()
    Some(image) => image.to_json()
  }
  { "node": self.node, "text": self.text, "style": self.style, "image": image }
}

///|
pub extend Span with ToJson::{to_json}

///|
pub(all) enum LineSpacing {
  Auto(Double)
  Exact(Double)
  AtLeast(Double)
}

///|
pub impl ToJson for LineSpacing with fn to_json(self) {
  let (rule, value) = match self {
    Auto(value) => ("auto", value)
    Exact(value) => ("exact", value)
    AtLeast(value) => ("atLeast", value)
  }
  { "rule": rule, "value": value }
}

///|
pub extend LineSpacing with ToJson::{to_json}

///|
pub(all) struct Paragraph {
  id : Int
  spans : Array[Span]
  before : Double
  after : Double
  line : LineSpacing
  left : Double
  right : Double
  first : Double
  align : String
  pageBreakBefore : Bool
} derive(ToJson)

///|
pub extend Paragraph with ToJson::{to_json}

///|
pub(all) struct PageSetup {
  width : Double
  height : Double
  top : Double
  right : Double
  bottom : Double
  left : Double
} derive(ToJson)

///|
pub extend PageSetup with ToJson::{to_json}

///|
pub(all) struct Flow {
  revision : Int
  page : PageSetup
  paragraphs : Array[Paragraph]
  diagnostics : Array[String]
  tables : Array[Table]
  headers : Array[Array[Paragraph]]
  headerDistance : Double
  additiveSpacing : Bool
} derive(ToJson)

///|
pub extend Flow with ToJson::{to_json}

///|
pub(all) struct PlacedRun {
  sources : Array[SourceRange]
  color : String
  text : String
  glyphs : Array[Glyph]
  bidi : Array[GlyphRun]
  x : Double
  baseline : Double
} derive(ToJson)

///|
pub extend PlacedRun with ToJson::{to_json}

///|
pub(all) struct SourceRange {
  node : Int
  start : Int
  end : Int
  offset : Int
} derive(ToJson)

///|
pub extend SourceRange with ToJson::{to_json}

///|
pub(all) struct Line {
  paragraph : Int
  text : String
  start : Int
  end : Int
  x : Double
  y : Double
  width : Double
  height : Double
  clip : Bool
  runs : Array[PlacedRun]
  images : Array[PlacedImage]
} derive(ToJson)

///|
pub extend Line with ToJson::{to_json}

///|
pub(all) struct PageFrame {
  width : Double
  height : Double
  lines : Array[Line]
  borders : Array[Border]
  fills : Array[Fill]
} derive(ToJson)

///|
pub extend PageFrame with ToJson::{to_json}

///|
pub(all) struct Layout {
  revision : Int
  profile : Map[String, String]
  pages : Array[PageFrame]
  diagnostics : Array[String]
  outlines : Array[Outline]
  fonts : Array[FontInfo]
} derive(ToJson)

///|
pub extend Layout with ToJson::{to_json}

///|
fn PageSetup::validate(self : PageSetup) -> Unit raise @failure.Failure {
  guard self.width >= 36 &&
    self.width <= 14400 &&
    self.height >= 36 &&
    self.height <= 14400 &&
    self.left >= 0 &&
    self.right >= 0 &&
    self.top >= 0 &&
    self.bottom >= 0 &&
    self.width - self.left - self.right >= 12 &&
    self.height - self.top - self.bottom >= 12 else {
    @failure.reject(
      "invalid-page", "Page dimensions or margins leave no usable area",
    )
  }
}

///|
pub(all) struct InlineImage {
  key : String
  width : Double
  height : Double
} derive(ToJson)

///|
pub extend InlineImage with ToJson::{to_json}

///|
pub(all) struct PlacedImage {
  key : String
  x : Double
  y : Double
  width : Double
  height : Double
} derive(ToJson)

///|
pub extend PlacedImage with ToJson::{to_json}

///|
pub(all) struct Border {
  x : Double
  y : Double
  width : Double
  height : Double
} derive(ToJson)

///|
pub extend Border with ToJson::{to_json}

///|
pub(all) struct Fill {
  x : Double
  y : Double
  width : Double
  height : Double
  color : String
} derive(ToJson)

///|
pub extend Fill with ToJson::{to_json}

///|
pub(all) struct Table {
  id : Int
  rows : Array[Array[Array[Paragraph]]]
  widths : Array[Double]
  align : String
  borders : Bool
  padding : Double
  verticalPadding : Double
  heights : Array[Double]
  fills : Array[Array[String]]
} derive(ToJson)

///|
pub extend Table with ToJson::{to_json}
