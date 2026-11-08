///|
priv enum DateFormatToken {
  Field(String, Int32)
  Literal(String)
}

///|
fn date_format(format : String) -> Array[DateFormatToken]? {
  guard format.length() > 0 && format.length() <= 256 else { return None }
  let chars = format.iter().to_array()
  guard !chars.any(c => {
    c < ' ' || ['\u{7f}', '\u{2028}', '\u{2029}'].contains(c)
  }) else {
    return None
  }
  let tokens : Array[DateFormatToken] = []
  let mut i = 0
  if format.has_prefix("[$-") {
    let mut end = 3
    while end < chars.length() && chars[end] != ']' {
      end += 1
    }
    guard end >= 4 && end <= 7 else { return None }
    let code = chars[3:end].iter().map(c => c.to_string()).join("")
    guard code.iter().all(c => "0123456789abcdefABCDEF".contains(c.to_string())) else {
      return None
    }
    let locale = @string.parse_int(code[:], base=16) catch { _ => return None }
    // shortcut: English names and unmapped system LCIDs use the fixed English culture; add other cultures with independent baselines.
    guard locale != 0xf800 && ((locale & 0x3ff) == 9 || locale >= 0xf000) else {
      return None
    }
    i = end + 1
  }
  while i < chars.length() {
    let c = chars[i]
    if c == '\\' {
      guard i + 1 < chars.length() else { return None }
      tokens.push(Literal(chars[i + 1].to_string()))
      i += 2
    } else if c == '"' {
      let start = i + 1
      i = start
      while i < chars.length() && chars[i] != '"' {
        i += 1
      }
      guard i < chars.length() else { return None }
      tokens.push(
        Literal(chars[start:i].iter().map(c => c.to_string()).join("")),
      )
      i += 1
    } else if i + 5 <= chars.length() &&
      chars[i:i + 5].iter().map(c => c.to_string()).join("").to_upper() ==
      "AM/PM" {
      tokens.push(Field("a", 0))
      i += 5
    } else if c == '.' &&
      i + 1 < chars.length() &&
      chars[i + 1] == '0' &&
      tokens.last() is Some(Field("s", _)) {
      guard i + 4 <= chars.length() &&
        chars[i + 1:i + 4].iter().all(c => c == '0') else {
        return None
      }
      tokens.push(Literal("."))
      tokens.push(Field("f", 3))
      i += 4
    } else {
      let field = c.to_string().to_lower()
      if ["y", "m", "d", "h", "s"].contains(field) {
        let start = i
        while i < chars.length() && chars[i].to_string().to_lower() == field {
          i += 1
        }
        let length = i - start
        guard (if field == "y" {
          length == 2 || length == 4
        } else if field == "m" {
          length <= 4
        } else {
          length <= 2
        }) else {
          return None
        }
        tokens.push(Field(field, length))
      } else {
        guard [' ', '-', '/', ':', ',', '.'].contains(c) else { return None }
        tokens.push(Literal(c.to_string()))
        i += 1
      }
    }
  }
  guard tokens.any(token => token is Field(_, _)) else { return None }
  // Resolve month/minute in source order as ONLYOFFICE NumFormat._prepareFormat does.
  for i in 0..<tokens.length() {
    guard tokens[i] is Field("m", length) && length <= 2 else { continue }
    let mut minute = false
    for j in (i + 1)..<tokens.length() {
      if tokens[j] is Field(field, _) && field != "a" {
        minute = field == "s"
        break
      }
    }
    if !minute {
      let mut second = false
      for j = i - 1; j >= 0; j = j - 1 {
        if tokens[j] is Field(field, _) {
          match field {
            "h" => {
              minute = true
              break
            }
            "s" => second = true
            "m" | "n" => {
              if second && field == "n" {
                second = false
              }
              break
            }
            "y" | "d" | "f" => if second { break }
            _ => ()
          }
        }
      }
      minute = minute || second
    }
    if minute {
      tokens[i] = Field("n", length)
    }
  }
  Some(tokens)
}

///|
fn date_number(
  value : Double,
  tokens : Array[DateFormatToken],
  date1904 : Bool,
) -> String {
  if value.is_nan() ||
    value < 0 ||
    value >= (if date1904 { 2957004 } else { 2958466 }) {
    return "########"
  }
  let mut day = value.floor().to_int()
  let mut fraction = value - value.floor()
  let parts : Array[Int32] = []
  for factor in [24, 60, 60] {
    fraction *= factor.to_double()
    parts.push(fraction.floor().to_int())
    fraction -= fraction.floor()
  }
  let mut millis = (fraction * 1000).round().to_int()
  if millis == 1000 {
    millis = 0
    parts[2] += 1
    for i = 2; i >= 0 && parts[i] == (if i == 0 { 24 } else { 60 }); i = i - 1 {
      parts[i] = 0
      if i == 0 {
        day += 1
      } else {
        parts[i - 1] += 1
      }
    }
  }
  let (year, month, date) = date_parts(day, date1904)
  if year > 9999 {
    return "########"
  }
  let hour = parts[0]
  let meridiem = tokens.any(token => token is Field("a", _))
  let fractional = tokens.any(token => token is Field("f", _))
  let output = StringBuilder()
  for token in tokens {
    let text = match token {
      Literal(text) => text
      Field(field, length) =>
        match field {
          "y" => padded(if length == 2 { year % 100 } else { year }, length)
          "m" =>
            match length {
              3 => date_month_names[month - 1]
              4 =>
                [
                  "January", "February", "March", "April", "May", "June", "July",
                  "August", "September", "October", "November", "December",
                ][month - 1]
              _ => padded(month, length)
            }
          "d" => padded(date, length)
          "h" =>
            padded(
              if meridiem {
                if hour % 12 == 0 {
                  12
                } else {
                  hour % 12
                }
              } else {
                hour
              },
              length,
            )
          "n" => padded(parts[1], length)
          "s" =>
            padded(
              parts[2] +
              (if !fractional {
                (millis.to_double() / 1000).round().to_int()
              } else {
                0
              }),
              length,
            )
          "f" => padded(millis, 3)
          _ => if hour < 12 { "AM" } else { "PM" }
        }
    }
    output.write_string(text)
  }
  output.to_string()
}
