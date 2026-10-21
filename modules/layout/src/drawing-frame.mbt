///|
pub(all) struct BasicShape {
  preset : String
  fill : String
  stroke : String
  lineWidth : Double
} derive(ToJson)

///|
pub extend BasicShape with ToJson::{to_json}

///|
pub(all) enum DrawingContent {
  Picture(String, Array[Double])
  Shape(BasicShape)
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
      }
  }
}

///|
pub extend DrawingContent with ToJson::{to_json}

///|
fn DrawingContent::copy(self : DrawingContent) -> DrawingContent {
  match self {
    Picture(key, crop) => Picture(key, crop.copy())
    Shape(_) => self
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
fn DrawingFrame::validate(self : DrawingFrame) -> Unit raise @failure.Failure {
  guard [self.width, self.height].all(value => {
    !value.is_nan() && !value.is_inf() && value >= 0 && value <= 14400
  }) else {
    @failure.reject("invalid-drawing", "Invalid drawing dimensions")
  }
  if self.anchor is Some(anchor) {
    anchor.validate()
  }
  match self.content {
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
    Shape(shape) => {
      guard ["rect", "ellipse", "line"].contains(shape.preset) &&
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
        shape.lineWidth <= 1584 else {
        @failure.reject("invalid-drawing", "Invalid basic shape frame")
      }
    }
  }
}

///|
pub(all) struct PlacedDrawingFrame {
  start : Int
  level : Int
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
  let horizontal = if self.width == 0 { 3.0 } else { 0.0 }
  let vertical = if self.height == 0 { 3.0 } else { 0.0 }
  (
    self.x - horizontal,
    self.y - vertical,
    self.width + 2 * horizontal,
    self.height + 2 * vertical,
  )
}
