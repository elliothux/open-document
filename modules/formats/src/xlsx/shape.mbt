///|
priv struct SheetShape {
  preset : String
  text_box : Bool
  fill : String
  stroke : String
  line_width : Double
  text : String
  font : String
  bold : Bool
  italic : Bool
  size : Double
  color : String
  left : Double
  top : Double
  right : Double
  bottom : Double
  wrap : Bool
  align : String
  vertical : String
} derive(Eq)

///|
pub(all) struct ShapeSettings {
  kind : String
  anchor : String
  rect : @layout.Border
  name : String
  description : String
  fill : String?
  stroke : String?
  line_width : Double
  text : String
  font : String
  bold : Bool
  italic : Bool
  size : Double
  color : String
  wrap : Bool
  align : String
  vertical : String
  insets : Array[Double]
}

///|
fn SheetObject::kind(self : SheetObject) -> String {
  match self.shape {
    None => "picture"
    Some(shape) => if shape.text_box { "textBox" } else { shape.preset }
  }
}

///|
fn SheetObject::shape_settings(
  self : SheetObject,
  rect : @layout.Border,
) -> ShapeSettings {
  let shape = self.shape.unwrap()
  {
    kind: self.kind(),
    anchor: self.anchor,
    rect,
    name: self.name,
    description: self.description,
    fill: if shape.fill.is_empty() {
      None
    } else {
      Some(shape.fill)
    },
    stroke: if shape.stroke.is_empty() {
      None
    } else {
      Some(shape.stroke)
    },
    line_width: shape.line_width,
    text: shape.text,
    font: shape.font,
    bold: shape.bold,
    italic: shape.italic,
    size: shape.size,
    color: shape.color,
    wrap: shape.wrap,
    align: shape.align,
    vertical: shape.vertical,
    insets: [shape.left, shape.top, shape.right, shape.bottom],
  }
}

///|
fn SheetObject::shape_json(self : SheetObject) -> Json {
  let shape = self.shape.unwrap()
  {
    "id": self.id,
    "kind": self.kind(),
    "anchor": self.anchor,
    "x": self.rect.x,
    "y": self.rect.y,
    "width": self.rect.width,
    "height": self.rect.height,
    "name": self.name,
    "description": self.description,
    "fill": if shape.fill.is_empty() {
      Json::null()
    } else {
      Json(shape.fill)
    },
    "stroke": if shape.stroke.is_empty() {
      Json::null()
    } else {
      Json(shape.stroke)
    },
    "lineWidth": shape.line_width,
    "text": shape.text,
    "font": shape.font,
    "bold": shape.bold,
    "italic": shape.italic,
    "size": shape.size,
    "color": shape.color,
    "wrap": shape.wrap,
    "align": shape.align,
    "vertical": shape.vertical,
    "insets": {
      "left": shape.left,
      "top": shape.top,
      "right": shape.right,
      "bottom": shape.bottom,
    },
  }
}

///|
pub fn Session::shapes(
  self : Session,
  revision : Int,
  sheet : String,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  self.font_context = Some((probe, profile.copy()))
  let current = self.sheets[self.sheet_index(sheet)]
  let mut reason = self.dimension_reason(current)
  let objects = self.sheet_objects(
    current,
    self.resolved_dimensions(current, probe, profile),
  ) catch {
    @failure.Failure(code="limit-exceeded", ..) as error => raise error
    @failure.Failure(message~, ..) => {
      reason = message
      []
    }
  }
  {
    "revision": self.revision,
    "sheet": sheet,
    "reason": reason,
    "items": objects
    .filter(object => object.shape is Some(_))
    .map(SheetObject::shape_json),
  }
}
