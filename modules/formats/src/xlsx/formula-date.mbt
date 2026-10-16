///|
fn date_function(
  name : String,
  args : Array[Expression],
  sheets : Array[Sheet],
  sheet : Int,
  calculated : Map[(Int, String), Value],
  work : FormulaWork,
  depth : Int,
) -> Value raise @failure.Failure {
  let numbers : Array[Double] = []
  for arg in args {
    let value = arg.evaluate(sheets, sheet, calculated, work, depth + 1)
    if value is Text(text) {
      work.spend(amount=text.length())
      if ["HOUR", "MINUTE", "SECOND"].contains(name) &&
        arg is Reference(_, _, _) {
        return Error("#VALUE!")
      }
    }
    let number = numeric_value(value)
    let number = if number is Error(_) &&
      value is Text(text) &&
      !["DATE", "TIME"].contains(name) &&
      !(name == "DAY" && arg is Reference(_, _, _)) {
      work.spend(amount=32)
      formula_date_text(text, work.date1904)
    } else {
      number
    }
    guard number is Number(number) else { return number }
    numbers.push(number)
  }
  let maximum = if work.date1904 { 2957003.0 } else { 2958465.0 }
  if name == "DATE" {
    let year = numbers[0]
    if year < 0 ||
      year >= 10000 ||
      numbers[1].abs() > 2147483647 ||
      numbers[2].abs() > 2147483647 {
      return Error("#NUM!")
    }
    let year = year.trunc().to_int()
    work.spend(amount=32)
    let serial = date_serial(
      if year < 1900 {
        year + 1900
      } else {
        year
      },
      numbers[1].trunc().to_int(),
      numbers[2].trunc().to_int(),
      work.date1904,
    ).to_double()
    return if serial < 0 || serial > maximum {
      Error("#NUM!")
    } else {
      Number(serial)
    }
  }
  if name == "TIME" {
    let total = numbers[0].trunc() * 3600 +
      numbers[1].trunc() * 60 +
      numbers[2].trunc()
    if total < 0 || total.is_inf() || total.is_nan() {
      return Error("#NUM!")
    }
    let days = total / 86400
    return Number(days - days.floor())
  }
  if numbers.any(value => value < 0 || value >= maximum + 1) {
    return Error("#NUM!")
  }
  if name == "DAYS" {
    return Number(numbers[0].floor() - numbers[1].floor())
  }
  let value = numbers[0]
  if ["YEAR", "MONTH", "DAY"].contains(name) {
    work.spend(amount=32)
    let (year, month, day) = date_parts(value.floor().to_int(), work.date1904)
    return Number(
      (match name {
        "YEAR" => year
        "MONTH" => month
        _ => day
      }).to_double(),
    )
  }
  let fraction = value - value.floor()
  let result = match name {
    "HOUR" => ((fraction * 24 * 1.0e8).round() / 1.0e8).floor() % 24
    "MINUTE" => ((fraction * 1440 * 1.0e8).round() / 1.0e8).floor() % 60
    // The reference rounds SECOND, without carrying into HOUR or MINUTE.
    _ => (((fraction * 86400 + 0.5) * 1.0e8).round() / 1.0e8).floor() % 60
  }
  Number(result)
}
