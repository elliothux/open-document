///|
fn date_integer(text : String) -> Int32? {
  guard !text.is_empty() &&
    text.length() <= 6 &&
    text.iter().all(character => character >= '0' && character <= '9') else {
    return None
  }
  Some(@string.parse_int(text[:])) catch {
    _ => None
  }
}

///|
// shortcut: Date text uses numeric ISO/US forms; extend with workbook locale support.
fn formula_date_text(text : String, date1904 : Bool) -> Value {
  let source = text.trim().to_owned().to_upper()
  guard source.length() <= 64 else { return Error("#VALUE!") }
  let meridiem = if source.has_suffix("AM") {
    1
  } else if source.has_suffix("PM") {
    2
  } else {
    0
  }
  let source = if meridiem == 0 {
    source
  } else {
    source[:source.length() - 2].trim().to_owned()
  }
  let tokens = source
    .replace_all(old="T", new=" ")
    .split(" ")
    .filter(part => !part.is_empty())
    .map(part => part.to_owned())
    .to_array()
  guard tokens.length() == 1 || tokens.length() == 2 else {
    return Error("#VALUE!")
  }
  let (date, time) = if tokens.length() == 2 {
    (tokens[0], tokens[1])
  } else if tokens[0].contains(":") {
    ("", tokens[0])
  } else {
    (tokens[0], "")
  }
  let mut serial = 0.0
  if !date.is_empty() {
    let separator = if date.contains("-") { "-" } else { "/" }
    let parts = date.split(separator).map(part => part.to_owned()).to_array()
    guard parts.length() == 3 else { return Error("#VALUE!") }
    let (year, month, day) = if parts[0].length() == 4 {
      (parts[0], parts[1], parts[2])
    } else if separator == "/" && parts[2].length() == 4 {
      (parts[2], parts[0], parts[1])
    } else {
      return Error("#VALUE!")
    }
    guard date_integer(year) is Some(year) &&
      date_integer(month) is Some(month) &&
      date_integer(day) is Some(day) &&
      year >= 1 &&
      year <= 9999 &&
      month >= 1 &&
      month <= 12 else {
      return Error("#VALUE!")
    }
    let days = if !date1904 && year == 1900 && month == 2 {
      29
    } else {
      calendar_months(year)[month - 1]
    }
    guard day >= 1 && day <= days else { return Error("#VALUE!") }
    serial = date_serial(year, month, day, date1904).to_double()
    if serial < 0 {
      return Error("#NUM!")
    }
  }
  if !time.is_empty() {
    let parts = time.split(":").map(part => part.to_owned()).to_array()
    guard parts.length() == 2 || parts.length() == 3 else {
      return Error("#VALUE!")
    }
    guard date_integer(parts[0]) is Some(hour) &&
      date_integer(parts[1]) is Some(minute) else {
      return Error("#VALUE!")
    }
    let second = if parts.length() == 2 {
      0.0
    } else {
      let digits = parts[2].split(".").to_array()
      guard digits.length() <= 2 &&
        digits.all(part => date_integer(part.to_owned()) is Some(_)) else {
        return Error("#VALUE!")
      }
      @string.parse_double(parts[2][:]) catch {
        _ => return Error("#VALUE!")
      }
    }
    guard minute < 60 &&
      second < 60 &&
      (if meridiem == 0 { hour < 24 } else { hour >= 1 && hour <= 12 }) else {
      return Error("#VALUE!")
    }
    let hour = if meridiem == 0 {
      hour
    } else {
      hour % 12 + (if meridiem == 2 { 12 } else { 0 })
    }
    serial += (hour.to_double() * 3600 + minute.to_double() * 60 + second) /
      86400
  } else if meridiem != 0 {
    return Error("#VALUE!")
  }
  Number(serial)
}
