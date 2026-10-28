///|
pub(all) struct BasicShape {
  preset : String
  fill : String
  stroke : String
  lineWidth : Double
  points : Array[(Double, Double)]
  strokeAlpha : Double
} derive(ToJson)

///|
pub extend BasicShape with ToJson::{to_json}

///|
pub(all) enum DrawingContent {
  Picture(String, Array[Double])
  Shape(BasicShape)
  TextBox(BasicShape, DrawingTextBox)
  Math(MathFormula)
  Chart(ChartFrame)
}

///|
pub impl ToJson for DrawingContent with fn to_json(self) {
  match self {
    Picture(key, crop) => { "kind": "picture", "key": key, "crop": crop }
    Shape(shape) =>
      {
        "kind": "shape",
        "preset": shape.preset,
        "fill": shape.fill,
        "stroke": shape.stroke,
        "lineWidth": shape.lineWidth,
        "points": shape.points,
        "strokeAlpha": shape.strokeAlpha,
      }
    TextBox(shape, text) => { "kind": "textBox", "shape": shape, "text": text }
    Math(formula) => { "kind": "math", "math": formula }
    Chart(chart) => { "kind": "chart", "chart": chart }
  }
}

///|
pub extend DrawingContent with ToJson::{to_json}

///|
fn DrawingContent::copy(self : DrawingContent) -> DrawingContent {
  match self {
    Picture(key, crop) => Picture(key, crop.copy())
    Shape(shape) => Shape({ ..shape, points: shape.points.copy(), })
    TextBox(shape, text) => TextBox(shape, text.copy())
    Math(formula) => Math(formula.copy())
    Chart(chart) => Chart(chart.copy())
  }
}

///|
pub(all) struct DrawingFrame {
  width : Double
  height : Double
  anchor : DrawingAnchor?
  content : DrawingContent
}

///|
pub impl ToJson for DrawingFrame with fn to_json(self) {
  {
    "width": self.width,
    "height": self.height,
    "anchor": self.anchor
    .map(anchor => anchor.to_json())
    .unwrap_or(Json::null()),
    "content": self.content,
  }
}

///|
pub extend DrawingFrame with ToJson::{to_json}

///|
/// Validate dimensions, drawing data and a text box's usable text area.
pub fn DrawingFrame::validate(
  self : DrawingFrame,
) -> Unit raise @failure.Failure {
  guard [self.width, self.height].all(value => {
    !value.is_nan() && !value.is_inf() && value >= 0 && value <= 14400
  }) else {
    @failure.reject("invalid-drawing", "Invalid drawing dimensions")
  }
  if self.anchor is Some(anchor) {
    anchor.validate()
  }
  match self.content {
    Chart(chart) => {
      guard self.width >= 180 && self.height >= 150 else {
        @failure.reject(
          "invalid-chart", "Chart frame requires at least 180 x 150 points",
        )
      }
      chart.data.validate()
    }
    Math(formula) => {
      guard self.anchor is None else {
        @failure.reject("unsupported-math", "Math must remain inline")
      }
      formula.validate()
    }
    Picture(key, crop) => {
      guard !key.is_empty() &&
        key.length() <= 4096 &&
        self.width > 0 &&
        self.height > 0 &&
        crop.length() == 4 &&
        crop.all(v => !v.is_nan() && !v.is_inf() && v >= 0 && v < 1) &&
        crop[0] + crop[2] < 1 &&
        crop[1] + crop[3] < 1 else {
        @failure.reject("invalid-image", "Invalid picture frame or crop")
      }
    }
    Shape(shape) | TextBox(shape, _) => {
      guard ["rect", "ellipse", "line", "polyline"].contains(shape.preset) &&
        (if shape.preset == "line" {
          self.width > 0 || self.height > 0
        } else {
          self.width > 0 && self.height > 0
        }) &&
        [shape.fill, shape.stroke].all(color => {
          color.is_empty() ||
          (
            color.length() == 6 &&
            color.iter().all(ch => ch.is_ascii_hexdigit())
          )
        }) &&
        !shape.lineWidth.is_nan() &&
        !shape.lineWidth.is_inf() &&
        shape.lineWidth >= 0 &&
        shape.lineWidth <= 1584 &&
        shape.strokeAlpha >= 0 &&
        shape.strokeAlpha <= 1 &&
        !shape.strokeAlpha.is_nan() &&
        (if shape.preset == "polyline" {
          shape.points.length() >= 2 &&
          shape.points.length() <= 4096 &&
          shape.fill.is_empty() &&
          !shape.stroke.is_empty() &&
          shape.lineWidth > 0 &&
          shape.points.all(point => {
            [point.0, point.1].all(value => {
              !value.is_nan() && !value.is_inf() && value >= 0 && value <= 1
            })
          })
        } else {
          shape.points.is_empty() && shape.strokeAlpha == 1
        }) else {
        @failure.reject("invalid-drawing", "Invalid basic shape frame")
      }
    }
  }
  if self.content is TextBox(shape, text) {
    guard !["line", "polyline"].contains(shape.preset) else {
      @failure.reject("invalid-drawing", "Line shapes cannot contain text")
    }
    text.validate()
    ignore(self.text_box_rect(shape, text))
  }
}

///|
pub(all) struct PlacedDrawingFrame {
  start : Int32
  level : Int32
  x : Double
  y : Double
  width : Double
  height : Double
  anchor : DrawingAnchor?
  content : DrawingContent
} derive(ToJson)

///|
pub extend PlacedDrawingFrame with ToJson::{to_json}

///|
fn PlacedDrawingFrame::interaction_bounds(
  self : PlacedDrawingFrame,
) -> (Double, Double, Double, Double) {
  let ink = match self.content {
    Shape(shape) =>
      if shape.preset == "polyline" {
        shape.lineWidth / 2 + 3
      } else {
        0.0
      }
    _ => 0.0
  }
  let horizontal = if self.width == 0 { 3.0 } else { ink }
  let vertical = if self.height == 0 { 3.0 } else { ink }
  (
    self.x - horizontal,
    self.y - vertical,
    self.width + 2 * horizontal,
    self.height + 2 * vertical,
  )
}

///|
fn PlacedDrawingFrame::ink_hit(
  self : PlacedDrawingFrame,
  x : Double,
  y : Double,
) -> Bool {
  guard self.content is Shape(shape) && shape.preset == "polyline" else {
    return true
  }
  let radius = shape.lineWidth / 2 + 3
  let x = x - self.x
  let y = y - self.y
  for index in 1..<shape.points.length() {
    let a = shape.points[index - 1]
    let b = shape.points[index]
    let ax = a.0 * self.width
    let ay = a.1 * self.height
    let dx = (b.0 - a.0) * self.width
    let dy = (b.1 - a.1) * self.height
    let length = dx * dx + dy * dy
    let ratio = if length == 0 {
      0.0
    } else {
      (((x - ax) * dx + (y - ay) * dy) / length).clamp(min=0, max=1)
    }
    let rx = x - ax - ratio * dx
    let ry = y - ay - ratio * dy
    if rx * rx + ry * ry <= radius * radius {
      return true
    }
  }
  false
}

///|
/// Accessible text for structured drawing content.
pub fn DrawingContent::alternative_text(self : DrawingContent) -> String? {
  match self {
    Math(formula) =>
      try {
        formula.expression.check()
        Some(formula.expression.linear_text())
      } catch {
        @failure.Failure(..) => None
      }
    Chart(chart) => Some(chart.data.title + ". " + chart.data.tsv())
    _ => None
  }
}
