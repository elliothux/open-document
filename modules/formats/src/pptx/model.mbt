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
  bullet : String
  bullet_style : @layout.TextStyle
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
  fit : Bool
}

///|
priv struct Object {
  id : String
  name : String
  kind : String
  source : Ref
  geometry : Geometry?
  preset : String
  fill : String
  stroke : String
  line_width : Double
  image : String?
  crop : Array[Double]
  paragraphs : Array[TextParagraph]
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
priv struct Slide {
  tree : Tree
  hidden : Bool
  objects : Array[Object]
  background : String
  diagnostics : Array[String]
  read_only : String
}

///|
priv struct Selection {
  slide : String
  object : String
  mode : String
  anchor : Int
  focus : Int
} derive(ToJson)

///|
priv struct History {
  edits : Array[(String, @xml.Edit)]
  before : Selection
  after : Selection
  bytes : Int
}

///|
priv struct Candidate {
  id : Int
  revision : Int
  selection : Selection
  slide : Slide
  edit : @xml.Edit?
  kind : String
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
