///|
pub(all) struct GradientStop {
  position : Double
  color : String
  opacity : Double
} derive(Eq, ToJson, Debug)

///|
pub extend GradientStop with Eq::{equal, not_equal}

///|
pub extend GradientStop with ToJson::{to_json}

///|
pub extend GradientStop with Debug::{to_repr}

///|
pub fn validate_gradient_stops(
  stops : Array[GradientStop],
) -> Unit raise @failure.Failure {
  guard stops.length() >= 2 && stops.length() <= 32 else {
    @failure.reject("invalid-drawing", "Gradients require 2..32 color stops")
  }
  for index, stop in stops {
    guard !stop.position.is_nan() &&
      !stop.position.is_inf() &&
      stop.position >= 0 &&
      stop.position <= 1 &&
      !stop.opacity.is_nan() &&
      !stop.opacity.is_inf() &&
      stop.opacity >= 0 &&
      stop.opacity <= 1 &&
      (index == 0 || stop.position >= stops[index - 1].position) &&
      stop.color.length() == 6 &&
      stop.color.iter().all(c => c.is_ascii_hexdigit()) else {
      @failure.reject("invalid-drawing", "Invalid ordered gradient stop")
    }
  }
}

///|
/// Validate a horizontal RGBA gradient before Canvas or PDF export.
pub fn validate_gradient(
  rect : Border,
  stops : Array[GradientStop],
) -> Unit raise @failure.Failure {
  validate_gradient_stops(stops)
  guard [rect.x, rect.y, rect.width, rect.height].all(v => {
      !v.is_nan() && !v.is_inf() && v.abs() <= 1000000000
    }) &&
    rect.width >= 0 &&
    rect.height >= 0 else {
    @failure.reject("invalid-drawing", "Invalid horizontal gradient rectangle")
  }
}
