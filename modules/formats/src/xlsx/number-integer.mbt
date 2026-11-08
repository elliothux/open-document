///|
priv enum IntegerFormatToken {
  Zero
  Literal(String)
}

///|
fn integer_format(
  format : String,
) -> (Array[IntegerFormatToken], Int32, Int32)? {
  guard format.length() > 0 && format.length() <= 256 else { return None }
  let chars = format.iter().to_array()
  guard !chars.any(c => {
    c < ' ' || ['\u{7f}', '\u{2028}', '\u{2029}'].contains(c)
  }) else {
    return None
  }
  let tokens : Array[IntegerFormatToken] = []
  let mut slots = 0
  let mut scale = 0
  let mut i = 0
  while i < chars.length() {
    match chars[i] {
      '0' => {
        tokens.push(Zero)
        slots += 1
        i += 1
      }
      '\\' => {
        guard i + 1 < chars.length() else { return None }
        tokens.push(Literal(chars[i + 1].to_string()))
        i += 2
      }
      '"' => {
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
      }
      ',' => {
        guard tokens.last() is Some(Zero) && chars[i:].iter().all(c => c == ',') else {
          return None
        }
        scale = (chars.length() - i) * 3
        break
      }
      _ => return None
    }
  }
  guard slots > 0 else { return None }
  Some((tokens, slots, scale))
}

///|
fn number_digits(value : Double, places : Int32, scale : Int32) -> String {
  guard !value.is_nan() && !value.is_inf() else { return "########" }
  let source = general_number(value.abs()).to_lower().split("e").to_array()
  let mantissa = source[0]
  let exponent = if source.length() == 2 {
    @string.parse_int(source[1]) catch {
      _ => return "########"
    }
  } else {
    0
  }
  let raw = mantissa.replace_all(old=".", new="").to_owned()
  let point = mantissa.find(".").unwrap_or(mantissa.length()) +
    exponent +
    places -
    scale
  let digits = if point < 0 {
    "0"
  } else if point >= raw.length() {
    raw + "0".repeat(point - raw.length())
  } else {
    let rounded = raw[:point].to_owned().to_array()
    let mut carry = raw[point] >= 53
    for i = rounded.length() - 1; carry && i >= 0; i = i - 1 {
      if rounded[i] == '9' {
        rounded[i] = '0'
      } else {
        rounded[i] = (rounded[i].to_int() + 1).to_char().unwrap()
        carry = false
      }
    }
    if carry {
      rounded.insert(0, '1')
    }
    if rounded.is_empty() {
      "0"
    } else {
      String::from_array(rounded)
    }
  }
  let mut first = 0
  while first + 1 < digits.length() && digits[first] == 48 {
    first += 1
  }
  digits[first:].to_owned()
}

///|
fn integer_number(
  value : Double,
  tokens : Array[IntegerFormatToken],
  slots : Int32,
  scale : Int32,
) -> String {
  let mut digits = number_digits(value, 0, scale)
  if digits == "########" {
    return digits
  }
  let output = StringBuilder()
  if value < 0 && digits != "0" {
    output.write_char('-')
  }
  digits = "0".repeat((slots - digits.length()).max(0)) + digits
  let mut cursor = 0
  for token in tokens {
    match token {
      Literal(text) => output.write_string(text)
      Zero => {
        let count = if cursor == 0 { digits.length() - slots + 1 } else { 1 }
        output.write_string(digits[cursor:cursor + count].to_owned())
        cursor += count
      }
    }
  }
  output.to_string()
}
