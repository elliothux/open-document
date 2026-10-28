///|
pub(all) struct PdfRedactionRegion {
  page : String
  x : Double
  y : Double
  width : Double
  height : Double
} derive(ToJson)

///|
pub extend PdfRedactionRegion with ToJson::{to_json}

///|
priv struct RedactionBounds {
  x : Double
  y : Double
  width : Double
  height : Double
}

///|
fn redaction_bounds(
  points : Array[Double],
  padding~ : Double = 0,
) -> RedactionBounds raise @failure.Failure {
  guard points.length() >= 2 &&
    points.length() % 2 == 0 &&
    points.length() <= 32768 &&
    points.all(n => !n.is_nan() && !n.is_inf() && n.abs() <= 1000000000) &&
    padding >= 0 &&
    !padding.is_nan() &&
    !padding.is_inf() else {
    @failure.reject(
      "protected-content", "Redaction geometry cannot be bounded safely",
    )
  }
  let mut left = points[0]
  let mut right = points[0]
  let mut top = points[1]
  let mut bottom = points[1]
  for i = 2; i < points.length(); i = i + 2 {
    left = left.min(points[i])
    right = right.max(points[i])
    top = top.min(points[i + 1])
    bottom = bottom.max(points[i + 1])
  }
  {
    x: left - padding,
    y: top - padding,
    width: right - left + padding * 2,
    height: bottom - top + padding * 2,
  }
}

///|
fn redaction_intersects(a : RedactionBounds, b : PdfRedactionRegion) -> Bool {
  // Include touching edges: anti-aliased strokes and pixels must not survive
  // merely because the selected rectangle ends exactly on their boundary.
  a.x <= b.x + b.width &&
  b.x <= a.x + a.width &&
  a.y <= b.y + b.height &&
  b.y <= a.y + a.height
}

///|
fn redaction_on_page(
  bounds : RedactionBounds,
  width : Double,
  height : Double,
) -> Bool {
  bounds.x >= -0.000001 &&
  bounds.y >= -0.000001 &&
  bounds.x + bounds.width <= width + 0.000001 &&
  bounds.y + bounds.height <= height + 0.000001
}

///|
fn redaction_path_bounds(
  path : Array[@layout.PathSegment],
  padding : Double,
) -> RedactionBounds raise @failure.Failure {
  let points : Array[Double] = []
  for segment in path {
    match segment {
      Move(x, y) | Line(x, y) => points.append([x, y])
      Cubic(a, b, c, d, x, y) => points.append([a, b, c, d, x, y])
      Close => ()
    }
  }
  redaction_bounds(points, padding~)
}

///|
fn PdfSession::redaction_regions(
  self : PdfSession,
  revision : Int32,
  regions : Array[PdfRedactionRegion],
) -> Unit raise @failure.Failure {
  self.check(revision)
  guard self.readOnlyReason.is_empty() else {
    @failure.reject("protected-content", self.readOnlyReason)
  }
  guard !regions.is_empty() && regions.length() <= 4096 else {
    @failure.reject("invalid-selection", "Choose bounded PDF redaction regions")
  }
  for region in regions {
    let page = self.page(region.page)
    guard [region.x, region.y, region.width, region.height].all(n => {
        !n.is_nan() && !n.is_inf()
      }) &&
      region.x >= 0 &&
      region.y >= 0 &&
      region.width > 0 &&
      region.height > 0 &&
      region.x + region.width <= page.width &&
      region.y + region.height <= page.height else {
      @failure.reject(
        "invalid-selection", "Redaction rectangles must fit inside their displayed pages",
      )
    }
  }
}
