///|
priv struct Geometry {
  x : Double
  y : Double
  width : Double
  height : Double
  rotation : Double
  flip_x : Bool
  flip_y : Bool
  matrix : @layout.Matrix
}

///|
priv struct TextRun {
  source : Ref?
  date_field : (Int, String)?
  math : @layout.MathFormula?
  text : String
  parts : Array[(@layout.TextStyle, String)]
}

///|
fn TextRun::style(self : TextRun) -> @layout.TextStyle {
  self.parts[0].0
}

///|
priv struct TextParagraph {
  source : Ref
  runs : Array[TextRun]
  before : ParagraphGap
  after : ParagraphGap
  spacing : @layout.LineSpacing
  left : Double
  right : Double
  first : Double
  align : String
  rtl : Bool
  bullet : String
  bullet_style : @layout.TextStyle
  bullet_size : TextSpacing
  list : ListFormat
  level : Int
  tabs : Array[ParagraphTab]
  inherited_tabs : Array[ParagraphTab]
  default_tab : Double
}

///|
priv enum ParagraphGap {
  Points(Double)
  Percent(Double)
}

///|
fn ParagraphGap::points(self : ParagraphGap, line_height : Double) -> Double {
  match self {
    Points(value) => value
    Percent(value) => line_height * value
  }
}

///|
priv struct Body {
  left : Double
  top : Double
  right : Double
  bottom : Double
  anchor : String
  wrap : Bool
  fit : String
}

///|
priv struct Object {
  id : String
  parent : String
  name : String
  kind : String
  source : Ref
  geometry : Geometry?
  preset : String
  polyline : Array[(Double, Double)]
  adjustments : (Double, Double, Double)
  fill : String
  gradient : (Array[@layout.GradientStop], Double, Bool)?
  stroke : String
  fill_alpha : Double
  stroke_alpha : Double
  fill_source : (Ref, Ref?)?
  stroke_source : (Ref, Ref?)?
  line_width : Double
  dash : String
  cap : String
  join : String
  miter : Double
  ends : (LineEnd, LineEnd)
  image : String?
  media : Media?
  tile : ImageTile?
  crop : Array[Double]
  insets : Array[Double]
  opacity : Double
  paragraphs : Array[TextParagraph]
  table : DrawingTable?
  chart : @chart.Resource?
  body : Body
  read_only : String
  text_reason : String
  diagnostic : String
}

///|
fn Object::text(self : Object) -> String {
  self.paragraphs
  .map(paragraph => paragraph.runs.map(run => run.text).join(""))
  .join("\n")
}

///|
fn Object::accessible_text(self : Object) -> String {
  self.paragraphs
  .map(paragraph => {
    paragraph.runs
    .map(run => {
      run.math
      .map(formula => formula.expression.linear_text())
      .unwrap_or(run.text)
    })
    .join("")
  })
  .join("\n")
}

///|
priv struct Slide {
  tree : Tree
  date_time : String?
  hidden : Bool
  objects : Array[Object]
  background : BackgroundFill
  diagnostics : Array[String]
  read_only : String
}

///|
priv struct Selection {
  slide : String
  object : String
  objects : Array[String]
  mode : String
  anchor : Int
  focus : Int
} derive(ToJson)

///|
priv struct History {
  edits : Array[(String, @xml.Edit)]
  mut created : (Slide, @xml.Document)?
  created_parts : Map[String, @xml.Document]
  created_media : Map[String, Bytes]
  mut deleted : Array[Slide]
  removed : Map[String, @xml.Document]
  before : Selection
  after : Selection
  bytes : Int
  media_bytes : Int
}

///|
priv struct Candidate {
  id : Int
  revision : Int
  selection : Selection
  slide : Slide
  edit : @xml.Edit?
  kind : String
  guide : GuideDrag?
  snap_lines : Array[Guide]
  snap_spacing : (Bool, Bool)
  snap_size : (Bool, Bool)
}

///|
priv struct TextGeometry {
  object : String
  matrix : @layout.Matrix
  lines : Array[@layout.Line]
}

///|
priv struct View {
  id : Int
  key : String
  revision : Int
  slide : String
  texts : Array[TextGeometry]
  result : Json
}
