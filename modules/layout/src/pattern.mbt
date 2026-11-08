///|
/// Validate an opaque 8x8 two-color bitmap repeated in document coordinates.
/// Each byte is a row, with the leftmost pixel in its most significant bit.
///
/// ```mbt check
/// test "Opaque bitmap patterns validate literal two-color masks" {
///   @layout.validate_pattern(
///     { x: 0, y: 0, width: 16, height: 16, },
///     6,
///     b"\x80\x40\x20\x10\x08\x04\x02\x01",
///     "ffffff",
///     "000000",
///   )
/// }
/// ```
pub fn validate_pattern(
  rect : Border,
  period : Double,
  mask : Bytes,
  zero : String,
  one : String,
) -> Unit raise @failure.Failure {
  guard mask.length() == 8 &&
    !period.is_nan() &&
    !period.is_inf() &&
    period >= 0.01 &&
    period <= 14400 &&
    [rect.x, rect.y, rect.width, rect.height].all(v => {
      !v.is_nan() && !v.is_inf() && v.abs() <= 1000000000
    }) &&
    rect.width >= 0 &&
    rect.height >= 0 &&
    [zero, one].all(color => {
      color.length() == 6 && color.iter().all(c => c.is_ascii_hexdigit())
    }) else {
    @failure.reject("invalid-drawing", "Invalid bitmap pattern fill")
  }
}
