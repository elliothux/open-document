///|
/// Validate a horizontal RGB gradient before Canvas or PDF export.
pub fn validate_gradient(
  rect : Border,
  start : String,
  end : String,
) -> Unit raise @failure.Failure {
  guard [rect.x, rect.y, rect.width, rect.height].all(v => {
      !v.is_nan() && !v.is_inf() && v.abs() <= 1000000000
    }) &&
    rect.width >= 0 &&
    rect.height >= 0 &&
    [start, end].all(color => {
      color.length() == 6 && color.iter().all(c => c.is_ascii_hexdigit())
    }) else {
    @failure.reject("invalid-drawing", "Invalid horizontal gradient rectangle")
  }
}
