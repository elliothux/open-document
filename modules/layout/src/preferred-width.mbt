///|
pub(all) struct PreferredWidth {
  value : Double
  percent : Bool
} derive(ToJson)

///|
pub extend PreferredWidth with ToJson::{to_json}

///|
pub fn PreferredWidth::new(
  value~ : Double = 0,
  percent~ : Bool = false,
) -> PreferredWidth {
  { value, percent, }
}

///|
fn PreferredWidth::resolve(
  self : PreferredWidth,
  available : Double,
) -> Double raise @failure.Failure {
  guard !self.value.is_nan() &&
    !self.value.is_inf() &&
    self.value >= 0 &&
    self.value <= (if self.percent { 1 } else { 14400 }) else {
    @failure.reject("invalid-table", "Invalid preferred table width")
  }
  if self.percent {
    self.value * available
  } else {
    self.value
  }
}
