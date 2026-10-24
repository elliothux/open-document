///|
pub(all) struct TextStyle {
  font : String
  size : Double
  color : String
  underline : Bool
  strike : Bool
  highlight : String
  script : String
  spacing : Double
} derive(ToJson)

///|
pub fn TextStyle::new(
  font : String,
  size : Double,
  color : String,
) -> TextStyle {
  {
    font,
    size,
    color,
    underline: false,
    strike: false,
    highlight: "",
    script: "baseline",
    spacing: 0,
  }
}

///|
fn TextStyle::render_size(self : TextStyle) -> Double {
  self.size * (if self.script == "baseline" { 1.0 } else { 0.65 })
}

///|
fn TextStyle::rise(self : TextStyle) -> Double {
  // ONLYOFFICE commonDefines.js: vaKSuper/vaKSub, in units of nominal font size.
  self.size *
  (match self.script {
    "superscript" => 0.35
    "subscript" => -0.141
    _ => 0.0
  })
}

///|
pub extend TextStyle with ToJson::{to_json}

///|
pub(all) struct Span {
  node : Int
  text : String
  style : TextStyle
  drawing : DrawingFrame?
  field : String
}

///|
pub impl ToJson for Span with fn to_json(self) {
  let image : Json = match self.drawing {
    None => Json::null()
    Some(image) => image.to_json()
  }
  {
    "node": self.node,
    "text": self.text,
    "style": self.style,
    "drawing": image,
    "field": self.field,
  }
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
pub(all) struct ParagraphMarker {
  text : String
  numbering : ParagraphNumbering?
  style : TextStyle
  align : String
  suffix : String
} derive(ToJson)

///|
pub extend ParagraphMarker with ToJson::{to_json}

///|
pub(all) struct Paragraph {
  id : Int
  container : Int
  nominalSize : Double
  spans : Array[Span]
  defaultTab : Double
  tabs : Array[TabStop]
  decimalSymbol : String
  expandSoftBreak : Bool
  before : Double
  after : Double
  line : LineSpacing
  left : Double
  right : Double
  first : Double
  align : String
  rtl : Bool
  marker : ParagraphMarker?
  pageBreakBefore : Bool
  keepLines : Bool
  keepNext : Bool
  widowControl : Bool
  readOnlyReason : String
} derive(ToJson)

///|
pub extend Paragraph with ToJson::{to_json}

///|
pub(all) struct Note {
  kind : String
  key : String
  paragraph : Int
  node : Int
  content : Array[Paragraph]
} derive(ToJson)

///|
pub extend Note with ToJson::{to_json}

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
  sectionBreaks : Array[SectionBreak]
  endnotesAt : String
  background : String
  pageBorders : PageBorders
  page : PageSetup
  pageNumbering : PageNumbering
  bookmarks : Map[String, (Int, Int, Int, Int)]
  outlineLevels : Map[Int, Int]
  columns : Columns
  paragraphs : Array[Paragraph]
  diagnostics : Array[String]
  tables : Array[Table]
  headers : Map[String, Array[Paragraph]]
  headerDistance : Double
  footers : Map[String, Array[Paragraph]]
  footerDistance : Double
  notes : Array[Note]
  differentFirst : Bool
  differentEven : Bool
  additiveSpacing : Bool
} derive(ToJson)

///|
pub extend Flow with ToJson::{to_json}

///|
pub(all) struct PlacedRun {
  start : Int
  sources : Array[SourceRange]
  color : String
  size : Double
  text : String
  glyphs : Array[Glyph]
  bidi : Array[GlyphRun]
  x : Double
  baseline : Double
  nominalSize : Double
  rise : Double
  decorations : Array[TextDecoration]
} derive(ToJson)

///|
pub(all) struct TextDecoration {
  x : Double
  width : Double
  underline : Bool
  strike : Bool
  highlight : String
} derive(ToJson)

///|
pub extend TextDecoration with ToJson::{to_json}

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
  container : Int
  baseLevel : Int
  text : String
  start : Int
  end : Int
  caretOnly : Bool
  repeated : Bool
  x : Double
  areaX : Double
  areaWidth : Double
  y : Double
  width : Double
  height : Double
  clip : Bool
  cellClip : Border?
  justified : Bool
  bars : Array[Double]
  marker : Array[PlacedRun]
  markerText : String
  runs : Array[PlacedRun]
  drawings : Array[PlacedDrawingFrame]
  carets : Array[Caret]
  readOnlyReason : String
} derive(ToJson)

///|
pub extend Line with ToJson::{to_json}

///|
pub(all) struct CellArea {
  x : Double
  y : Double
  width : Double
  height : Double
  paragraphs : Array[Int]
} derive(ToJson)

///|
pub extend CellArea with ToJson::{to_json}

///|
pub(all) struct PageFrame {
  width : Double
  height : Double
  lines : Array[Line]
  borders : Array[TableStroke]
  fills : Array[Fill]
  pageBorders : Array[Fill]
  cellAreas : Array[CellArea]
} derive(ToJson)

///|
pub extend PageFrame with ToJson::{to_json}

///|
pub(all) struct Layout {
  background : String
  revision : Int
  shapedParagraphs : Int
  reusedParagraphs : Int
  reflowedPages : Int
  reusedPages : Int
  profile : Map[String, String]
  pages : Array[PageFrame]
  running : Array[Array[Line]]
  sectionNumbering : Array[PageNumbering]
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
pub(all) struct CellMargins {
  top : Double
  right : Double
  bottom : Double
  left : Double
} derive(ToJson, Eq)

///|
pub extend CellMargins with ToJson::{to_json}

///|
pub extend CellMargins with Eq::{not_equal, equal}

///|
pub(all) struct BorderStyle {
  width : Double
  color : String
} derive(ToJson, Eq, Debug)

///|
pub extend BorderStyle with ToJson::{to_json}

///|
pub extend BorderStyle with Eq::{equal, not_equal}

///|
pub extend BorderStyle with Debug::{to_repr}

///|
pub(all) struct TableBorders {
  horizontal : Array[Array[BorderStyle]]
  vertical : Array[Array[BorderStyle]]
} derive(ToJson)

///|
pub extend TableBorders with ToJson::{to_json}

///|
pub(all) struct TableStroke {
  rect : Border
  color : String
  width : Double
} derive(ToJson)

///|
pub extend TableStroke with ToJson::{to_json}

///|
pub(all) struct Table {
  id : Int
  autoFit : Bool
  preferredWidth : PreferredWidth
  preferredWidths : Array[Array[PreferredWidth]]
  headerRows : Int
  beforeParagraph : Int
  rows : Array[Array[Array[Paragraph]]]
  columnSpans : Array[Array[Int]]
  rowSpans : Array[Array[Int]]
  widths : Array[Double]
  align : String
  borders : TableBorders
  margins : Array[Array[CellMargins]]
  heights : Array[Double]
  exactHeights : Array[Bool]
  splitRows : Array[Bool]
  fills : Array[Array[String]]
  verticalAligns : Array[Array[String]]
} derive(ToJson)

///|
pub extend Table with ToJson::{to_json}
