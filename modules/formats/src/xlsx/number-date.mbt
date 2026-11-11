///|
priv enum DateFormatToken {
  Locale(Int32)
  Field(String, Int32)
  Elapsed(String, Int32)
  Literal(String)
}

///|
let date_weekday_names : ReadOnlyArray[String] = [
  "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
]

///|
let date_chinese_months : ReadOnlyArray[String] = [
  "一", "二", "三", "四", "五", "六", "七", "八", "九", "十", "十一",
  "十二",
]

///|
fn date_local_month(locale : Int32, month : Int32, length : Int32) -> String {
  let number = month.to_string()
  let name = if (locale & 0x3ff) == 4 &&
    (length != 3 || ![0x804, 0x7804].contains(locale)) {
    date_chinese_months[month - 1]
  } else {
    number
  }
  if length == 5 {
    name[:1].to_owned()
  } else if length == 3 && (locale & 0x3ff) != 4 {
    number
  } else {
    name + (if (locale & 0x3ff) == 0x12 { "월" } else { "月" })
  }
}

///|
fn date_local_weekday(locale : Int32, day : Int32, length : Int32) -> String {
  let short = ["日", "一", "二", "三", "四", "五", "六"][day]
  match locale & 0x3ff {
    0x11 =>
      ["日", "月", "火", "水", "木", "金", "土"][day] +
      (if length == 4 { "曜日" } else { "" })
    0x12 =>
      ["일", "월", "화", "수", "목", "금", "토"][day] +
      (if length == 4 { "요일" } else { "" })
    _ =>
      (if length == 4 {
        "星期"
      } else if [0x404, 0xc04, 0x1404, 0x7c04].contains(locale) {
        "週"
      } else {
        "周"
      }) +
      short
  }
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
  let mut localized = false
  let mut elapsed = false
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
    localized = [
      0x404, 0x804, 0xc04, 0x1004, 0x1404, 0x7804, 0x7c04, 0x11, 0x411, 0x12, 0x412,
    ].contains(locale)
    // shortcut: other mapped cultures need independent date baselines.
    guard localized ||
      (locale != 0xf800 && ((locale & 0x3ff) == 9 || locale >= 0xf000)) else {
      return None
    }
    if localized {
      tokens.push(Locale(locale))
      if format.has_suffix(";@") {
        chars.truncate(chars.length() - 2)
      }
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
    } else if c == '[' {
      guard !elapsed && i + 2 < chars.length() else { return None }
      let field = chars[i + 1].to_string().to_lower()
      guard ["h", "m", "s"].contains(field) else { return None }
      let length = if chars[i + 2].to_string().to_lower() == field {
        2
      } else {
        1
      }
      guard chars.get(i + length + 1) == Some(']') else { return None }
      tokens.push(Elapsed(field, length))
      elapsed = true
      i += length + 2
    } else if c == '.' &&
      i + 1 < chars.length() &&
      chars[i + 1] == '0' &&
      tokens.last() is Some(Field("s", _) | Elapsed("s", _)) {
      let mut end = i + 1
      while end < chars.length() && chars[end] == '0' {
        end += 1
      }
      let length = end - i - 1
      guard length == 3 || (elapsed && length < 3) else { return None }
      tokens.push(Literal("."))
      tokens.push(Field("f", length))
      i = end
    } else {
      let field = c.to_string().to_lower()
      if ["y", "m", "d", "h", "s"].contains(field) ||
        (localized && field == "a") {
        let start = i
        while i < chars.length() && chars[i].to_string().to_lower() == field {
          i += 1
        }
        let length = i - start
        guard (if field == "y" {
          length == 2 || length == 4
        } else if field == "m" {
          length <= 5
        } else if field == "d" {
          length <= 4
        } else if field == "a" {
          length == 3 || length == 4
        } else {
          length <= 2
        }) else {
          return None
        }
        tokens.push(Field(if field == "a" { "d" } else { field }, length))
      } else {
        guard [' ', '-', '/', ':', ',', '.'].contains(c) else { return None }
        tokens.push(Literal(c.to_string()))
        i += 1
      }
    }
  }
  guard elapsed || tokens.any(token => token is Field(_, _)) else {
    return None
  }
  // Resolve month/minute in source order as ONLYOFFICE NumFormat._prepareFormat does.
  for i in 0..<tokens.length() {
    guard tokens[i] is Field("m", length) && length <= 2 else { continue }
    let mut minute = false
    for j in (i + 1)..<tokens.length() {
      if tokens[j] is Elapsed(field, _) {
        minute = field == "s"
        break
      }
      if tokens[j] is Field(field, _) && field != "a" {
        minute = field == "s"
        break
      }
    }
    if !minute {
      let mut second = false
      for j = i - 1; j >= 0; j = j - 1 {
        if tokens[j] is Elapsed(field, _) {
          minute = field == "h"
          break
        }
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
  guard !elapsed ||
    (
      !tokens.any(token => token is Field("y" | "m" | "d" | "a", _)) &&
      tokens.iter().filter(token => token is Field("f", _)).count() <= 1
    ) else {
    return None
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
  let elapsed = tokens.any(token => token is Elapsed(_, _))
  let precision = match
    tokens.iter().find_first(token => token is Field("f", _)) {
    Some(Field(_, length)) => length
    _ => 0
  }
  let quantum = if precision > 0 {
    [100, 10, 1][precision - 1]
  } else if elapsed &&
    tokens.any(token => token is (Field("s", _) | Elapsed("s", _))) {
    1000
  } else {
    1
  }
  let mut millis = (fraction * 1000 / quantum.to_double()).round().to_int() *
    quantum
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
  let locale = match tokens.get(0) {
    Some(Locale(locale)) => locale
    _ => 0
  }
  let output = StringBuilder()
  for token in tokens {
    let text = match token {
      Locale(_) => ""
      Literal(text) => text
      Elapsed(field, length) => {
        let hours = day.to_int64() * 24L + hour.to_int64()
        let minutes = hours * 60L + parts[1].to_int64()
        let value = match field {
          "h" => hours
          "m" => minutes
          _ => minutes * 60L + parts[2].to_int64()
        }
        value.to_string().pad_start(length, '0')
      }
      Field(field, length) =>
        match field {
          "y" => padded(if length == 2 { year % 100 } else { year }, length)
          "m" =>
            if locale != 0 && length >= 3 {
              date_local_month(locale, month, length)
            } else {
              match length {
                3 => date_month_names[month - 1]
                4 =>
                  [
                    "January", "February", "March", "April", "May", "June", "July",
                    "August", "September", "October", "November", "December",
                  ][month - 1]
                5 => date_month_names[month - 1][:1].to_owned()
                _ => padded(month, length)
              }
            }
          "d" =>
            if length <= 2 {
              padded(date, length)
            } else if locale != 0 {
              date_local_weekday(locale, date_weekday(day, date1904), length)
            } else {
              let name = date_weekday_names[date_weekday(day, date1904)]
              if length == 3 {
                name[:3].to_owned()
              } else {
                name
              }
            }
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
              (if precision == 0 {
                (millis.to_double() / 1000).round().to_int()
              } else {
                0
              }),
              length,
            )
          "f" => padded(millis / quantum, length)
          _ =>
            match locale & 0x3ff {
              4 => if hour < 12 { "上午" } else { "下午" }
              0x11 => if hour < 12 { "午前" } else { "午後" }
              0x12 => if hour < 12 { "오전" } else { "오후" }
              _ => if hour < 12 { "AM" } else { "PM" }
            }
        }
    }
    output.write_string(text)
  }
  output.to_string()
}
