///|
fn series_weekday(serial : Int, date1904 : Bool) -> Int {
  let value = (serial + (if date1904 { 5 } else { 6 })) % 7
  if value < 0 {
    value + 7
  } else {
    value
  }
}

///|
fn series_workday(serial : Int, step : Int, date1904 : Bool) -> Int {
  if step == 0 {
    return serial
  }
  let direction = if step > 0 { 1 } else { -1 }
  let mut result = serial + direction
  while [0, 6].contains(series_weekday(result, date1904)) {
    result += direction
  }
  let remaining = step.abs() - 1
  result += remaining / 5 * 7 * direction
  for _ in 0..<(remaining % 5) {
    result += direction
    while [0, 6].contains(series_weekday(result, date1904)) {
      result += direction
    }
  }
  result
}

///|
fn date_series_values(
  seed : Double,
  unit : String,
  step : Double,
  count : Int,
  date1904 : Bool,
  expectedDay? : Int,
) -> Array[Double] raise @failure.Failure {
  let limit = if date1904 { 2957004.0 } else { 2958466.0 }
  guard !seed.is_nan() && !seed.is_inf() && seed >= 0 && seed < limit else {
    @failure.reject(
      "invalid-operation", "Date series seed is outside the workbook calendar",
    )
  }
  let fraction = seed - seed.floor()
  let (seed_year, seed_month, seed_day) = date_parts(
    seed.floor().to_int(),
    date1904,
  )
  let mut year = seed_year
  let mut month = seed_month
  let mut day = seed_day
  let mut serial = seed.floor().to_int()
  let values : Array[Double] = [seed]
  for offset in 1..<count {
    let value = match unit {
      "day" => seed + step * offset.to_double()
      "weekday" => {
        serial = series_workday(serial, step.to_int(), date1904)
        serial.to_double() + fraction
      }
      _ => {
        if unit == "month" {
          let next = month - 1 + step.to_int()
          year += calendar_floor(next, 12)
          month = next - calendar_floor(next, 12) * 12 + 1
          day = expectedDay
            .unwrap_or(seed_day)
            .min(
              if !date1904 && year == 1900 && month == 2 {
                29
              } else {
                calendar_months(year)[month - 1]
              },
            )
        } else {
          year += step.to_int()
        }
        guard year >= (if date1904 { 1904 } else { 1900 }) && year <= 9999 else {
          @failure.reject(
            "invalid-operation", "Date series exceeds the workbook calendar",
          )
        }
        serial = date_serial(year, month, day, date1904).to_int()
        // ONLYOFFICE addYears rolls February 29 into March in a non-leap year.
        if unit == "year" {
          let (next_year, next_month, next_day) = date_parts(serial, date1904)
          year = next_year
          month = next_month
          day = next_day
        }
        serial.to_double() + fraction
      }
    }
    guard !value.is_nan() && !value.is_inf() && value >= 0 && value < limit else {
      @failure.reject(
        "invalid-operation", "Date series exceeds the workbook calendar",
      )
    }
    values.push(value)
  }
  values
}
