///|
priv enum NumberPart {
  Visible(String)
  Skip(String)
  Repeat(String)
  Digits(String, Int32, Bool)
  SourceText
  ValueText(String)
  Percent
  Sign(Char)
}

///|
priv struct NumberSection {
  parts : Array[NumberPart]
  color : String?
  percent : Int32
}

///|
fn number_section(source : String) -> NumberSection? {
  let chars = source.iter().to_array()
  let parts : Array[NumberPart] = []
  let mut color = None
  let mut numeric = false
  let mut text = false
  let mut percent = 0
  let mut i = 0
  if chars.get(0) == Some('[') {
    let end = source.find("]").unwrap_or(0)
    guard end > 1 && end <= 8 else { return None }
    color = match source[1:end].to_owned().to_lower() {
      "black" => Some("000000")
      "blue" => Some("0000ff")
      "cyan" => Some("00ffff")
      "green" => Some("00ff00")
      "magenta" => Some("ff00ff")
      "red" => Some("ff0000")
      "white" => Some("ffffff")
      "yellow" => Some("ffff00")
      _ => return None
    }
    i = end + 1
  }
  while i < chars.length() {
    match chars[i] {
      '\\' | '_' | '*' as kind => {
        guard i + 1 < chars.length() else { return None }
        let value = chars[i + 1].to_string()
        parts.push(
          if kind == '_' {
            Skip(value)
          } else if kind == '*' {
            Repeat(value)
          } else {
            Visible(value)
          },
        )
        i += 2
      }
      '"' => {
        let start = i + 1
        i = start
        while i < chars.length() && chars[i] != '"' {
          i += 1
        }
        guard i < chars.length() else { return None }
        parts.push(
          Visible(chars[start:i].iter().map(c => c.to_string()).join("")),
        )
        i += 1
      }
      '@' => {
        guard !numeric && !text && percent == 0 else { return None }
        text = true
        parts.push(SourceText)
        i += 1
      }
      '%' => {
        guard !text else { return None }
        percent += 1
        parts.push(Percent)
        i += 1
      }
      '0' | '#' | '?' => {
        guard !numeric && !text else { return None }
        numeric = true
        let start = i
        while i < chars.length() && ['0', '#', '?', ',', '.'].contains(chars[i]) {
          i += 1
        }
        let code = chars[start:i].iter().map(c => c.to_string()).join("")
        let pieces = code.split(".").to_array()
        guard pieces.length() <= 2 else { return None }
        let integer = pieces[0].to_owned()
        guard !integer.is_empty() &&
          !integer.has_prefix(",") &&
          !integer.has_suffix(",") &&
          !integer.contains(",,") else {
          return None
        }
        let mask = integer.replace_all(old=",", new="")
        let mut zero = false
        for c in mask.iter() {
          if c == '0' {
            zero = true
          } else if zero || (c != '#' && c != '?') {
            return None
          }
        }
        let places = if pieces.length() == 2 {
          guard pieces[1].length() > 0 &&
            pieces[1].length() <= 30 &&
            pieces[1].iter().all(c => c == '0') else {
            return None
          }
          pieces[1].length()
        } else {
          0
        }
        parts.push(Digits(mask, places, integer.contains(",")))
      }
      '+' | '-' as c => {
        parts.push(Sign(c))
        i += 1
      }
      ' ' | '(' | ')' | '$' | '¥' as c => {
        parts.push(Visible(c.to_string()))
        i += 1
      }
      _ => return None
    }
  }
  let unique : Array[NumberPart] = []
  let mut repeated = false
  for part in parts {
    if part is Repeat(_) {
      if repeated {
        continue
      }
      repeated = true
    }
    unique.push(part)
  }
  Some({ parts: unique, color, percent, })
}

///|
fn section_format(format : String) -> Array[NumberSection]? {
  guard format.length() > 0 && format.length() <= 256 else { return None }
  let sections : Array[NumberSection] = []
  let source = StringBuilder()
  let mut quoted = false
  let mut escaped = false
  for c in format.iter() {
    guard c >= ' ' && !['\u{7f}', '\u{2028}', '\u{2029}'].contains(c) else {
      return None
    }
    if c == ';' && !quoted && !escaped {
      guard sections.length() < 3 &&
        number_section(source.to_string()) is Some(section) else {
        return None
      }
      sections.push(section)
      source.reset()
    } else {
      source.write_char(c)
      if escaped {
        escaped = false
      } else if c == '\\' || (!quoted && (c == '_' || c == '*')) {
        escaped = true
      } else if c == '"' {
        quoted = !quoted
      }
    }
  }
  guard !quoted &&
    !escaped &&
    number_section(source.to_string()) is Some(section) else {
    return None
  }
  sections.push(section)
  Some(sections)
}
