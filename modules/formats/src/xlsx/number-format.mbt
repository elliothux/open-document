///|
fn supported_format(format : String) -> Bool {
  format == "General" ||
  scientific_format(format) is Some(_) ||
  date_format(format) is Some(_) ||
  integer_format(format) is Some(_) ||
  section_format(format) is Some(_)
}

///|
fn padded(value : Int32, length : Int32) -> String {
  let text = value.to_string()
  "0".repeat((length - text.length()).max(0)) + text
}

///|
fn number_overflow(value : Value, format : String, date1904 : Bool) -> Bool {
  guard value is Number(number) else { return false }
  if number.is_nan() || number.is_inf() {
    return true
  }
  guard date_format(format) is Some(tokens) else { return false }
  date_number(number, tokens, date1904) == "########"
}

///|
fn formatted(value : Value, format : String, date1904 : Bool) -> String {
  if format == "General" {
    return if value is Number(number) {
      general_display(number)
    } else {
      value.display()
    }
  }
  if section_display(value, format) is Some(section) {
    return section.display()
  }
  guard value is Number(value) else { return value.display() }
  if scientific_format(format) is Some((places, digits, sign)) {
    return scientific_number(value, places, digits, sign)
  }
  if date_format(format) is Some(tokens) {
    return date_number(value, tokens, date1904)
  }
  if integer_format(format) is Some((tokens, slots, scale)) {
    return integer_number(value, tokens, slots, scale)
  }
  Number(value).display()
}
