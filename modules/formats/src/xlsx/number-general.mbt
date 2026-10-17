///|
fn general_number(value : Double) -> String {
  // shortcut: Keep the existing notation until General formatting uses measured column width.
  if value == 0 {
    return "0"
  }
  let source = value.abs().to_string().to_lower().split("e").collect()
  let mantissa = source[0].to_owned()
  let exponent = if source.length() == 2 {
    @string.parse_int(source[1]) catch {
      _ => return value.to_string()
    }
  } else {
    0
  }
  let digits = mantissa.replace_all(old=".", new="")
  let mut leading = 0
  while leading < digits.length() && digits[leading] == 48 {
    leading += 1
  }
  let mut point = mantissa.find(".").unwrap_or(mantissa.length()) +
    exponent -
    leading
  let digits = digits[leading:].to_owned()
  let rounded = digits[:digits.length().min(15)].to_owned().to_array()
  let mut carry = digits.length() > 15 && digits[15] >= 53
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
    point += 1
  }
  while rounded.length() > 1 && rounded.last() == Some('0') {
    ignore(rounded.pop())
  }
  let digits = String::from_array(rounded)
  let result = if source.length() == 2 {
    let exponent = point - 1
    digits[:1].to_owned() +
    (if digits.length() > 1 { "." + digits[1:].to_owned() } else { "" }) +
    "e" +
    (if exponent >= 0 { "+" } else { "" }) +
    exponent.to_string()
  } else if point <= 0 {
    "0." + "0".repeat(-point) + digits
  } else if point >= digits.length() {
    digits + "0".repeat(point - digits.length())
  } else {
    digits[:point].to_owned() + "." + digits[point:].to_owned()
  }
  (if value < 0 { "-" } else { "" }) + result
}
