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
      !["DATE", "TIME", "WEEKDAY", "WEEKNUM", "ISOWEEKNUM"].contains(name) &&
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
  if ["WEEKDAY", "WEEKNUM", "ISOWEEKNUM"].contains(name) {
    return date_week_value(name, numbers, work)
  }
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

///|
fn date_week_value(
  name : String,
  numbers : Array[Double],
  work : FormulaWork,
) -> Value raise @failure.Failure {
  let mode = if name == "ISOWEEKNUM" {
    21.0
  } else {
    numbers.get(1).unwrap_or(1.0)
  }
  let allowed = if name == "WEEKDAY" {
    [1, 2, 3, 11, 12, 13, 14, 15, 16, 17]
  } else {
    [1, 2, 11, 12, 13, 14, 15, 16, 17, 21]
  }
  guard allowed.any(value => value.to_double() == mode) else {
    return Error("#NUM!")
  }
  let value = numbers[0]
  if value < 0 {
    return Error(if name == "WEEKDAY" { "#VALUE!" } else { "#NUM!" })
  }
  guard value < (if work.date1904 { 2957004.0 } else { 2958466.0 }) else {
    return Error("#NUM!")
  }
  let serial = value.floor().to_int()
  let mode = mode.to_int()
  let start = match mode {
    1 | 17 => 0
    2 | 3 | 11 | 21 => 1
    _ => mode - 10
  }
  if name == "WEEKDAY" {
    let day = (series_weekday(serial, work.date1904) - start + 7) % 7
    return Number((day + (if mode == 3 { 0 } else { 1 })).to_double())
  }
  work.spend(amount=32)
  let base = if work.date1904 {
    calendar_ordinal(1904, 1, 1)
  } else {
    calendar_ordinal(1899, 12, 30)
  }
  // ONLYOFFICE week numbers normalize the fictitious leap day to March 1.
  let ordinal = base +
    serial.to_int64() +
    (if !work.date1904 && serial == 60 { 1L } else { 0L })
  if mode == 21 {
    let thursday = ordinal + (3 - (ordinal.to_int() + 6) % 7).to_int64()
    let (year, _, _) = calendar_parts(thursday)
    return Number(
      ((thursday - calendar_ordinal(year, 1, 1)) / 7 + 1).to_double(),
    )
  }
  let (year, _, _) = calendar_parts(ordinal)
  // The reference labels serials 0/1 as 1900 for ordinary week numbering.
  let year = if !work.date1904 && serial <= 1 { 1900 } else { year }
  let first = calendar_ordinal(year, 1, 1)
  let offset = (first.to_int() % 7 - start + 7) % 7
  Number(((ordinal - first + offset.to_int64() + 7) / 7).to_double())
}
