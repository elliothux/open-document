///|
fn copied_date_serial(
  value : Double,
  source : Bool,
  target : Bool,
) -> Double raise @failure.Failure {
  if source == target {
    return value
  }
  guard !value.is_nan() &&
    !value.is_inf() &&
    value >= 0 &&
    value < (if source { 2957004.0 } else { 2958466.0 }) else {
    @failure.reject(
      "invalid-operation", "Copied date is outside the source calendar",
    )
  }
  let epoch = date_serial(1904, 1, 1, false).to_double()
  let changed = value + (if source { epoch } else { -epoch })
  guard changed >= 0 && changed < (if target { 2957004.0 } else { 2958466.0 }) else {
    @failure.reject(
      "invalid-operation", "Copied date cannot be represented in the target calendar",
    )
  }
  changed
}

///|
fn CopiedCell::calendar_value(
  self : CopiedCell,
  source : Bool,
  target : Bool,
) -> Value raise @failure.Failure {
  if source != target &&
    self.value is Number(value) &&
    ["date", "datetime"].contains(
      series_calendar_kind(self.format.numberFormat.unwrap()),
    ) {
    Number(copied_date_serial(value, source, target))
  } else {
    self.value
  }
}

///|
fn copied_date_bound(
  text : String,
  source : Bool,
  target : Bool,
) -> String raise @failure.Failure {
  if source == target || text.is_empty() {
    return text
  }
  let value = match shift_rule_expression(text) {
    Some(Constant(Number(value))) | Some(Unary("+", Constant(Number(value)))) =>
      value
    Some(Unary("-", Constant(Number(value)))) => -value
    _ => return text
  }
  (if text.has_prefix("=") { "=" } else { "" }) +
  Number(copied_date_serial(value, source, target)).display()
}
