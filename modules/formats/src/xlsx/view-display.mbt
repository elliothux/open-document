///|
fn ViewSettings::display(
  self : ViewSettings,
  formula : String?,
  value : Value,
  format : String,
  date1904 : Bool,
  hidden~ : Bool,
) -> String {
  guard self.formulas else { return formatted(value, format, date1904) }
  if formula is Some(source) {
    return if hidden { "" } else { "=" + source }
  }
  guard value is Number(number) else { return value.display() }
  let fields = date_format(format)
  let percents = section_display(value, format)
    .map(section => section.percent)
    .unwrap_or(0)
  if percents > 0 {
    let mut percent = number
    for _ in 0..<percents {
      percent *= 100
    }
    return if percent.is_inf() {
      "########"
    } else {
      Number(percent).display() + "%".repeat(percents)
    }
  }
  guard fields is Some(tokens) else { return value.display() }
  // The SDK uses fixed ISO dates and 24-hour times instead of a host locale.
  let time = tokens.any(token => {
      token is Field(field, _) && ["h", "n", "s", "f", "a"].contains(field)
    }) ||
    number != number.floor()
  let date = tokens.any(token => {
      token is Field(field, _) && ["y", "m", "d"].contains(field)
    }) ||
    number >= 1
  if number < 0 || number >= (if date1904 { 2957004 } else { 2958466 }) {
    return value.display()
  }
  (if date { formatted(value, "yyyy-mm-dd", date1904) } else { "" }) +
  (if date && time { " " } else { "" }) +
  (if time { formatted(value, "hh:mm:ss", date1904) } else { "" })
}
