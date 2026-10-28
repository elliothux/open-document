///|
let date_month_names : ReadOnlyArray[String] = [
  "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
]

///|
fn calendar_floor(value : Int32, divisor : Int32) -> Int32 {
  value / divisor - (if value % divisor < 0 { 1 } else { 0 })
}

///|
fn calendar_year_days(year : Int32) -> Int64 {
  let previous = year - 1
  previous.to_int64() * 365 +
  calendar_floor(previous, 4).to_int64() -
  calendar_floor(previous, 100).to_int64() +
  calendar_floor(previous, 400).to_int64()
}

///|
fn calendar_months(year : Int32) -> FixedArray[Int32] {
  [
    31,
    if year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) {
      29
    } else {
      28
    },
    31,
    30,
    31,
    30,
    31,
    31,
    30,
    31,
    30,
    31,
  ]
}

///|
fn calendar_ordinal(year : Int32, month : Int32, day : Int32) -> Int64 {
  let months = calendar_months(year)
  let mut ordinal = calendar_year_days(year) + day.to_int64()
  for index in 0..<(month - 1) {
    ordinal += months[index].to_int64()
  }
  ordinal
}

///|
fn date_serial(
  year : Int32,
  month : Int32,
  day : Int32,
  date1904 : Bool,
) -> Int64 {
  let year = year + calendar_floor(month - 1, 12)
  let month = (month - 1) % 12
  let month = (if month < 0 { month + 12 } else { month }) + 1
  // Preserve the reference's explicit fictitious leap-day constructor.
  if !date1904 && year == 1900 && month == 2 && day == 29 {
    return 60
  }
  serial_from_ordinal(calendar_ordinal(year, month, day), date1904)
}

///|
fn serial_from_ordinal(ordinal : Int64, date1904 : Bool) -> Int64 {
  if date1904 {
    ordinal - calendar_ordinal(1904, 1, 1)
  } else {
    ordinal -
    calendar_ordinal(1899, 12, 31) +
    (if ordinal >= calendar_ordinal(1900, 3, 1) { 1 } else { 0 })
  }
}

///|
fn date_parts(serial : Int32, date1904 : Bool) -> (Int32, Int32, Int32) {
  if !date1904 && serial == 60 {
    return (1900, 2, 29)
  }
  if !date1904 && serial == 0 {
    return (1900, 1, 0)
  }
  let ordinal = if date1904 {
    serial.to_int64() + calendar_ordinal(1904, 1, 1)
  } else {
    serial.to_int64() +
    calendar_ordinal(1899, 12, 31) -
    (if serial > 60 { 1 } else { 0 })
  }
  calendar_parts(ordinal)
}

///|
fn calendar_parts(ordinal : Int64) -> (Int32, Int32, Int32) {
  let mut year = 1
  let mut end = 10001
  // Binary search bounds calendar conversion independently of the input year.
  while year + 1 < end {
    let middle = (year + end) / 2
    if calendar_year_days(middle) < ordinal {
      year = middle
    } else {
      end = middle
    }
  }
  let mut day = (ordinal - calendar_year_days(year) - 1).to_int()
  let months = calendar_months(year)
  let mut month = 0
  while month < 11 && day >= months[month] {
    day -= months[month]
    month += 1
  }
  (year, month + 1, day + 1)
}
