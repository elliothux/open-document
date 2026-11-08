///|
fn general_number(value : Double) -> String {
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

///|
fn general_display(value : Double, limit~ : Int32 = 11) -> String {
  guard !value.is_nan() && !value.is_inf() else { return "########" }
  if value == 0 {
    return "0"
  }
  let source = general_number(value.abs()).to_lower().split("e").to_array()
  let mantissa = source[0]
  let exponent = if source.length() == 2 {
    @string.parse_int(source[1]) catch {
      _ => return "########"
    }
  } else {
    0
  }
  let digits = mantissa.replace_all(old=".", new="")
  let mut first = 0
  while first < digits.length() && digits[first] == 48 {
    first += 1
  }
  let mut point = mantissa.find(".").unwrap_or(mantissa.length()) +
    exponent -
    first
  let mut budget = limit.max(1).min(11)
  let mut significant = digits.length() - first
  let text = for ;; {
    let exponent_units = 2 + point.abs().to_string().length().max(2)
    let plain_digits = budget - 2 + point
    let scientific_digits = if budget - exponent_units > 2 {
      budget - exponent_units - 1
    } else {
      (budget - exponent_units).max(0).min(1)
    }
    let scientific = point > budget ||
      (
        point <= 0 &&
        plain_digits < scientific_digits &&
        !(plain_digits > 0 && significant <= plain_digits)
      )
    if scientific {
      if budget < exponent_units + 1 {
        break section_display(Number(value), "0").unwrap().display()
      }
      budget -= exponent_units
    }
    let decimal_point = if scientific { 1 } else { point }
    let places = if decimal_point > 0 {
      (budget - 1 - decimal_point).max(0)
    } else {
      (budget - 2).max(0)
    }
    let rounding = if decimal_point <= 0 {
      (budget + decimal_point - 2).max(0)
    } else if decimal_point < 15 && decimal_point <= budget {
      if decimal_point + 1 < budget {
        budget - 1
      } else {
        decimal_point
      }
    } else {
      0
    }
    if rounding > 0 {
      let rounded = scientific_number(value, rounding - 1, 2, true)
      let rounded_point = (@string.parse_int(rounded.split("E").to_array()[1]) catch {
          _ => return "########"
        }) +
        1
      if rounded_point != point {
        // Native General masks re-evaluate exponent carries with the remaining digit budget.
        point = rounded_point
        significant = 1
        continue
      }
    }
    break if scientific {
      scientific_number(value, places, exponent_units - 2, true)
    } else {
      section_display(
        Number(value),
        "0" + (if places > 0 { "." + "0".repeat(places) } else { "" }),
      )
      .unwrap()
      .display()
    }
  }
  let parts = text.split("E").to_array()
  let mut number = parts[0].to_owned()
  if number.contains(".") {
    while number.has_suffix("0") {
      number = number[:number.length() - 1].to_owned()
    }
    if number.has_suffix(".") {
      number = number[:number.length() - 1].to_owned()
    }
  }
  number + (if parts.length() == 2 { "E" + parts[1].to_owned() } else { "" })
}
