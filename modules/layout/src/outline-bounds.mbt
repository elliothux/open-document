///|
priv struct GlyphOutlinePen {
  path : StringBuilder
  bounds : Array[Double]
  mut valid : Bool
}

///|
fn GlyphOutlinePen::point(
  self : GlyphOutlinePen,
  x : Double,
  y : Double,
) -> Unit {
  if x.is_nan() ||
    y.is_nan() ||
    x.is_inf() ||
    y.is_inf() ||
    x.abs() > 1000000000 ||
    y.abs() > 1000000000 {
    self.valid = false
    return
  }
  if self.bounds.is_empty() {
    self.bounds.append([x, y, x, y])
  } else {
    self.bounds[0] = self.bounds[0].min(x)
    self.bounds[1] = self.bounds[1].min(y)
    self.bounds[2] = self.bounds[2].max(x)
    self.bounds[3] = self.bounds[3].max(y)
  }
}

///|
/// Bounds collected from actual glyph outline endpoints and curve controls.
/// These conservatively enclose ink even for negative bearings and composites.
pub fn TextProbe::source_glyph_bounds(
  self : TextProbe,
  index : Int32,
  glyph : UInt32,
) -> Array[Double] raise @failure.Failure {
  self.check()
  guard index >= 0 && index < self.fonts.length() else {
    @failure.reject("missing-font", "Unknown source font")
  }
  let (key, _, _) = self.outline(index, glyph)
  self.outline_boxes.get(key).unwrap_or([]).copy()
}
