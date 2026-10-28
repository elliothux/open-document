///|
priv struct ContourPen {
  contours : Array[Array[(Double, Double, Bool)]]
  mut invalid : Bool
}

///|
fn ContourPen::point(
  self : ContourPen,
  x : Double,
  y : Double,
  on : Bool,
) -> Unit {
  if x.is_nan() ||
    y.is_nan() ||
    x.is_inf() ||
    y.is_inf() ||
    x.abs() > 32767 ||
    y.abs() > 32767 {
    self.invalid = true
    return
  }
  if self.contours.last() is Some(points) {
    if points.length() >= 65535 {
      self.invalid = true
    } else {
      points.push((x, y, on))
    }
  } else {
    self.invalid = true
  }
}

///|
/// Obtain flattened native quadratic contours without font programs or metadata.
/// Cubic outlines are rejected rather than approximated for clean reconstruction.
pub fn TextProbe::source_glyph_contours(
  self : TextProbe,
  index : Int32,
  glyph : UInt32,
) -> Array[Array[(Double, Double, Bool)]] raise @failure.Failure {
  self.check()
  guard index >= 0 && index < self.fonts.length() else {
    @failure.reject("missing-font", "Unknown source font")
  }
  let pen : ContourPen = { contours: [], invalid: false, }
  let funcs = @draw.DrawFuncs::new()
  funcs.set_move_to(
    Some((pen : ContourPen, _, x, y) => {
      pen.contours.push([])
      pen.point(x, y, true)
    }),
  )
  funcs.set_line_to(Some((pen, _, x, y) => pen.point(x, y, true)))
  funcs.set_quadratic_to(
    Some((pen, _, a, b, x, y) => {
      pen.point(a, b, false)
      pen.point(x, y, true)
    }),
  )
  funcs.set_cubic_to(Some((pen, _, _, _, _, _, _, _) => pen.invalid = true))
  funcs.set_close_path(Some((_, _) => ()))
  match self.fonts[index].font.draw_glyph_or_fail(glyph, funcs, pen) {
    Ok(true) => ()
    _ =>
      @failure.reject(
        "protected-content", "Source glyph cannot be canonically reconstructed",
      )
  }
  guard !pen.invalid && pen.contours.length() <= 32767 else {
    @failure.reject(
      "protected-content", "Source glyph exceeds clean contour limits",
    )
  }
  pen.contours
}
