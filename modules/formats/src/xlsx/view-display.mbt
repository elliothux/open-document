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
  if supported_format(format) && format.has_suffix("%") {
    let percent = number * 100
    return if percent.is_inf() {
      "########"
    } else {
      Number(percent).display() + "%"
    }
  }
  guard supported_format(format) &&
    !["General", "@"].contains(format) &&
    !["0", "#", "$", "¥"].any(prefix => format.has_prefix(prefix)) else {
    return value.display()
  }
  // The SDK uses fixed ISO dates and 24-hour times instead of a host locale.
  let time = format.contains(":") || number != number.floor()
  let date = !format.contains(":") || number >= 1
  if number < 0 || number >= (if date1904 { 2957004 } else { 2958466 }) {
    return value.display()
  }
  (if date { formatted(value, "yyyy-mm-dd", date1904) } else { "" }) +
  (if date && time { " " } else { "" }) +
  (if time { formatted(value, "hh:mm:ss", date1904) } else { "" })
}
