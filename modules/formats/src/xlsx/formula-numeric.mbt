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
fn factorial_product(
  number : Double,
  step : Int32,
  work : FormulaWork,
) -> Double raise @failure.Failure {
  let mut result = 1.0
  for factor = number.floor().to_int(); factor > 0; factor = factor - step {
    work.spend()
    result *= factor.to_double()
  }
  result
}

///|
fn decimal_integer(number : Double) -> Double raise @failure.Failure {
  // JavaScript parseInt reads the mantissa when the number uses exponential notation.
  if number.abs() >= 1.0e21 || (number != 0 && number.abs() < 1.0e-6) {
    try
      @string.parse_double(number.to_string().split("e").head().unwrap())
    catch {
      _ => @failure.reject("invalid-number", "Invalid integer argument")
    } noraise {
      value => value.trunc()
    }
  } else {
    number.trunc()
  }
}

///|
fn rounded_multiple(value : Double, step : Double) -> Value {
  if step == 0 {
    return Number(0)
  }
  if (value < 0 && step > 0) || (value > 0 && step < 0) {
    return Error("#NUM!")
  }
  let shifted = value + step / 2
  let scale = @math.pow(10, @math.log10(shifted.abs()).floor() - 14)
  let adjusted = (shifted + 0.5 * (shifted / shifted.abs()) * scale) / scale
  let quotient = adjusted /
    adjusted.abs() *
    adjusted.abs().floor() *
    scale /
    step
  let quotient = quotient +
    5 *
    (quotient / quotient.abs()) *
    @math.pow(10, @math.log10(quotient.abs()).floor() - 15)
  // The native reference converts the corrected quotient with JavaScript ToInt32.
  let integer = if quotient.is_nan() || quotient.is_inf() {
    0.0
  } else {
    quotient.trunc() % 4294967296
  }
  let signed = if integer >= 2147483648 {
    integer - 4294967296
  } else if integer < -2147483648 {
    integer + 4294967296
  } else {
    integer
  }
  finite_result(signed * step)
}

///|
fn numeric_function(
  name : String,
  args : Array[Expression],
  sheets : Array[Sheet],
  sheet : Int32,
  values : Map[(Int32, String), Value],
  work : FormulaWork,
  depth : Int32,
) -> Value raise @failure.Failure {
  let numbers : Array[Double] = []
  for arg in args {
    let value = if [
        "FACT", "FACTDOUBLE", "COMBIN", "COMBINA", "MROUND", "QUOTIENT",
      ].contains(name) {
      arg.scalar_argument(sheets, sheet, values, work, depth + 1)
    } else {
      arg.evaluate(sheets, sheet, values, work, depth + 1)
    }
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
    "FACT" | "FACTDOUBLE" => {
      let number = numbers[0]
      let maximum = if name == "FACT" { 170 } else { 300 }
      if number < 0 || number.floor() > maximum.to_double() {
        return Error("#NUM!")
      }
      let step = if name == "FACT" { 1 } else { 2 }
      finite_result(factorial_product(number, step, work))
    }
    "COMBIN" | "COMBINA" => {
      let first = numbers[0]
      let second = numbers[1]
      if first < 0 || second < 0 || first < second {
        return Error("#NUM!")
      }
      let (total, chosen) = if name == "COMBINA" {
        let chosen = decimal_integer(second)
        (decimal_integer(first) + chosen - 1, chosen)
      } else {
        (first, second)
      }
      if total < 0 || chosen > total {
        return Error("#NUM!")
      }
      if total.floor() > 170 {
        return if name == "COMBIN" && first == second {
          Number(1)
        } else {
          Error("#NUM!")
        }
      }
      // Keep native factorial division, including independently flooring total - chosen.
      finite_result(
        factorial_product(total, 1, work) /
        (
          factorial_product(chosen, 1, work) *
          factorial_product(total - chosen, 1, work)
        ),
      )
    }
    "PI" => Number(@math.PI)
    "MROUND" => rounded_multiple(numbers[0], numbers[1])
    "QUOTIENT" => {
      if numbers[1] == 0 {
        return Error("#DIV/0!")
      }
      let quotient = numbers[0] / numbers[1]
      if quotient.is_nan() || quotient.is_inf() {
        Error("#NUM!")
      } else {
        Number(decimal_integer(quotient))
      }
    }
    "SIN" => finite_result(@math.sin(numbers[0]))
    "COS" => finite_result(@math.cos(numbers[0]))
    "TAN" => finite_result(@math.tan(numbers[0]))
    "SINH" => finite_result(@math.sinh(numbers[0]))
    "COSH" => finite_result(@math.cosh(numbers[0]))
    "TANH" => finite_result(@math.tanh(numbers[0]))
    "ACOSH" => finite_result(@math.acosh(numbers[0]))
    "ASINH" => finite_result(@math.asinh(numbers[0]))
    "ATANH" => finite_result(@math.atanh(numbers[0]))
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
    "SIGN" =>
      Number(if numbers[0] < 0 { -1 } else if numbers[0] > 0 { 1 } else { 0 })
    "CEILING" | "FLOOR" => {
      let value = numbers[0]
      let step = numbers[1]
      if step == 0 {
        return Number(0)
      }
      if (value > 0 && step < 0) || (name == "FLOOR" && value < 0 && step > 0) {
        return Error("#NUM!")
      }
      let quotient = value / step
      if quotient.is_inf() || quotient.is_nan() {
        return Error("#NUM!")
      }
      if quotient == 0 {
        return Number(0)
      }
      // ONLYOFFICE legacy functions use a signed fifteen-digit tolerance.
      let tolerance = (if quotient < 0 { -5.0 } else { 5.0 }) *
        @math.pow(10, @math.log10(quotient.abs()).floor() - 15)
      let mut multiple = quotient.floor()
      if name == "FLOOR" {
        multiple = (quotient + tolerance).floor()
      } else if (quotient - multiple).abs() > tolerance {
        multiple += 1
      }
      finite_result(multiple * step)
    }
    "TRUNC" => {
      let places = numbers.get(1).unwrap_or(0).min(20)
      let digits = if places < 0 { -(-places).round() } else { places.round() }
      let scale = @math.pow(10, digits)
      finite_result((numbers[0] * scale).trunc() / scale)
    }
    "CEILING.MATH" | "CEILING.PRECISE" | "FLOOR.MATH" | "FLOOR.PRECISE" => {
      let value = numbers[0]
      let step = numbers.get(1).unwrap_or(1).abs()
      if step == 0 || value == 0 {
        return Number(0)
      }
      let quotient = value / step
      if quotient.is_inf() || quotient.is_nan() {
        return Error("#NUM!")
      }
      let up = name.has_prefix("CEILING")
      let up = if name.has_suffix(".MATH") &&
        value < 0 &&
        numbers.get(2).unwrap_or(0) != 0 {
        !up
      } else {
        up
      }
      finite_result(
        (if up { quotient.ceil() } else { quotient.floor() }) * step,
      )
    }
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
