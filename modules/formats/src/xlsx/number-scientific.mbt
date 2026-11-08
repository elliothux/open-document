///|
fn scientific_format(format : String) -> (Int32, Int32, Bool)? {
  guard format.length() >= 4 && format.length() <= 40 else { return None }
  let parts = format.to_upper().split("E").to_array()
  guard parts is [mantissa, exponent] &&
    exponent.length() >= 2 &&
    exponent.length() <= 7 &&
    (exponent[0] == 43 || exponent[0] == 45) &&
    exponent[1:].iter().all(ch => ch == '0') else {
    return None
  }
  let places = if mantissa == "0" {
    0
  } else {
    guard mantissa.has_prefix("0.") &&
      mantissa.length() >= 3 &&
      mantissa.length() <= 32 &&
      mantissa[2:].iter().all(ch => ch == '0') else {
      return None
    }
    mantissa.length() - 2
  }
  Some((places, exponent.length() - 1, exponent[0] == 43))
}

///|
fn scientific_number(
  value : Double,
  places : Int32,
  exponent_digits : Int32,
  positive_sign : Bool,
) -> String {
  guard !value.is_nan() && !value.is_inf() else { return "########" }
  // Decimal digits avoid overflow/underflow when normalizing extreme exponents.
  let source = general_number(value.abs()).to_lower().split("e").to_array()
  let mantissa = source[0]
  let mut exponent = if source.length() == 2 {
    @string.parse_int(source[1]) catch {
      _ => return "########"
    }
  } else {
    0
  }
  let raw = mantissa.replace_all(old=".", new="")
  let mut first = 0
  while first < raw.length() && raw[first] == 48 {
    first += 1
  }
  let count = places + 1
  let digits = if first == raw.length() {
    exponent = 0
    Array::make(count, '0')
  } else {
    exponent += mantissa.find(".").unwrap_or(mantissa.length()) - first - 1
    let significant = raw[first:]
    let digits = significant[:count.min(significant.length())]
      .to_owned()
      .to_array()
    let mut carry = significant.length() > count && significant[count] >= 53
    for i = digits.length() - 1; carry && i >= 0; i = i - 1 {
      if digits[i] == '9' {
        digits[i] = '0'
      } else {
        digits[i] = (digits[i].to_int() + 1).to_char().unwrap()
        carry = false
      }
    }
    if carry {
      digits[0] = '1'
      exponent += 1
    }
    while digits.length() < count {
      digits.push('0')
    }
    digits
  }
  let text = String::from_array(digits)
  (if value < 0 { "-" } else { "" }) +
  text[:1].to_owned() +
  (if places > 0 { "." + text[1:].to_owned() } else { "" }) +
  "E" +
  (if exponent < 0 { "-" } else if positive_sign { "+" } else { "" }) +
  padded(exponent.abs(), exponent_digits)
}
