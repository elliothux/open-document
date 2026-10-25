///|
fn rounded_decimal(value : Double, places : Double, mode : String) -> Value {
  if value == 0 || places >= 324 {
    return Number(value)
  }
  let places = places.trunc()
  if places < -308 {
    return if mode == "ROUNDUP" { Error("#NUM!") } else { Number(0) }
  }
  // Decimal digits preserve ties such as 1.005 without binary scaling noise.
  let source = value.abs().to_string().to_lower().split("e").collect()
  let mantissa = source[0].to_owned()
  let exponent = if source.length() == 2 {
    @string.parse_int(source[1]) catch {
      _ => return Error("#NUM!")
    }
  } else {
    0
  }
  let point = mantissa.find(".").unwrap_or(mantissa.length()) + exponent
  let digits = mantissa.replace_all(old=".", new="")
  let keep = point + places.to_int()
  if keep >= digits.length() {
    return Number(value)
  }
  let mut carry = if mode == "ROUNDUP" {
    digits[keep.max(0):].iter().any(character => character != '0')
  } else {
    mode == "ROUND" && keep >= 0 && digits[keep] >= 53
  }
  let retained = digits[:keep.max(0)].to_owned().to_array()
  for index = retained.length() - 1; carry && index >= 0; index = index - 1 {
    if retained[index] == '9' {
      retained[index] = '0'
    } else {
      retained[index] = (retained[index].to_int() + 1).to_char().unwrap()
      carry = false
    }
  }
  if carry {
    retained.insert(0, '1')
  }
  if retained.is_empty() {
    return Number(0)
  }
  let text = (if value < 0 { "-" } else { "" }) +
    String::from_array(retained) +
    "e" +
    (-places.to_int()).to_string()
  let rounded = @string.parse_double(text[:]) catch {
    _ => return Error("#NUM!")
  }
  finite_result(rounded)
}

///|
fn numeric_function(
  name : String,
  args : Array[Expression],
  sheets : Array[Sheet],
  sheet : Int,
  values : Map[(Int, String), Value],
  work : FormulaWork,
  depth : Int,
) -> Value raise @failure.Failure {
  let numbers : Array[Double] = []
  for arg in args {
    let value = arg.evaluate(sheets, sheet, values, work, depth + 1)
    if value is Text(text) {
      work.spend(amount=text.length())
    }
    if (name == "ROUND" || name == "ROUNDDOWN") &&
      arg is Reference(_, _, _) &&
      value is Text(_) {
      return Error("#VALUE!")
    }
    match numeric_value(value) {
      Number(value) => numbers.push(value)
      value => return value
    }
  }
  match name {
    "PI" => Number(@math.PI)
    "SIN" => finite_result(@math.sin(numbers[0]))
    "COS" => finite_result(@math.cos(numbers[0]))
    "TAN" => finite_result(@math.tan(numbers[0]))
    "SINH" => finite_result(@math.sinh(numbers[0]))
    "COSH" => finite_result(@math.cosh(numbers[0]))
    "TANH" => finite_result(@math.tanh(numbers[0]))
    "ACOSH" => finite_result(@math.acosh(numbers[0]))
    "ASINH" => finite_result(@math.asinh(numbers[0]))
    "ACOS" => finite_result(@math.acos(numbers[0]))
    "ASIN" => finite_result(@math.asin(numbers[0]))
    "ATAN" => finite_result(@math.atan(numbers[0]))
    "EXP" => finite_result(@math.exp(numbers[0]))
    "LN" => finite_result(@math.ln(numbers[0]))
    "LOG10" => finite_result(@math.log10(numbers[0]))
    "LOG" => {
      let base = numbers.get(1).unwrap_or(10)
      if numbers[0] <= 0 || base <= 0 {
        Error("#NUM!")
      } else if base == 1 {
        Error("#DIV/0!")
      } else {
        finite_result(@math.ln(numbers[0]) / @math.ln(base))
      }
    }
    "ATAN2" =>
      if numbers[0] == 0 && numbers[1] == 0 {
        Error("#DIV/0!")
      } else {
        finite_result(@math.atan2(numbers[1], numbers[0]))
      }
    "RADIANS" => finite_result(numbers[0] * @math.PI / 180)
    "DEGREES" => finite_result(numbers[0] * 180 / @math.PI)
    "ABS" => Number(numbers[0].abs())
    "INT" => Number(numbers[0].floor())
    "SQRT" => finite_result(numbers[0].sqrt())
    "POWER" => {
      let base = numbers[0]
      let exponent = numbers[1]
      if base == 0 && exponent < 0 {
        return Error("#DIV/0!")
      }
      if base >= 0 || exponent.floor() == exponent {
        return finite_result(@math.pow(base, exponent))
      }
      // ONLYOFFICE accepts a negative real root only when its rounded inverse restores the base.
      let root = -@math.pow(-base, exponent)
      let inverse = @math.pow(root, 1 / exponent)
      if !inverse.is_nan() && (inverse + 0.5).floor() == (base + 0.5).floor() {
        finite_result(root)
      } else {
        Error("#NUM!")
      }
    }
    "MOD" => {
      if numbers[1] == 0 {
        return Error("#DIV/0!")
      }
      finite_result(numbers[0] - numbers[1] * (numbers[0] / numbers[1]).floor())
    }
    "ROUND" | "ROUNDUP" | "ROUNDDOWN" =>
      rounded_decimal(numbers[0], numbers[1], name)
    _ => abort("Unexpected numeric function")
  }
}
