///|
let relative_filter_periods : ReadOnlyArray[String] = [
  "yesterday", "today", "tomorrow", "lastWeek", "thisWeek", "nextWeek", "lastMonth",
  "thisMonth", "nextMonth", "lastQuarter", "thisQuarter", "nextQuarter", "lastYear",
  "thisYear", "nextYear", "yearToDate",
]

///|
fn filter_current_date(
  text : String,
) -> (Int32, Int32, Int32) raise @failure.Failure {
  let parts = filter_date_parts(text)
  guard parts.length() == 3 &&
    parts[2] <= calendar_months(parts[0])[parts[1] - 1] else {
    @failure.reject(
      "invalid-operation", "Current date requires a Gregorian YYYY-MM-DD",
    )
  }
  (parts[0], parts[1], parts[2])
}

///|
fn validate_relative_filter(
  period : String,
  cache : (Double, Double)?,
) -> Unit raise @failure.Failure {
  guard relative_filter_periods.contains(period) else {
    @failure.reject("invalid-operation", "Unknown relative date filter period")
  }
  if cache is Some((start, end)) {
    guard !start.is_nan() &&
      !start.is_inf() &&
      !end.is_nan() &&
      !end.is_inf() &&
      start < end else {
      @failure.reject("invalid-operation", "Invalid relative date filter cache")
    }
  }
}

///|
fn Session::relative_filter_interval(
  self : Session,
  period : String,
) -> (Double, Double) raise @failure.Failure {
  validate_relative_filter(period, None)
  guard self.calendar_date is Some((year, month, day)) else {
    @failure.reject(
      "invalid-operation", "A current calendar date is required for relative filters",
    )
  }
  let today = calendar_ordinal(year, month, day)
  let days = fn(first : Int32, end : Int32) {
    (
      serial_from_ordinal(today + first.to_int64(), self.date1904).to_double(),
      serial_from_ordinal(today + end.to_int64(), self.date1904).to_double(),
    )
  }
  match period {
    "yesterday" => days(-1, 0)
    "today" => days(0, 1)
    "tomorrow" => days(1, 2)
    "yearToDate" =>
      (date_serial(year, 1, 1, self.date1904).to_double(), days(0, 1).1)
    _ => {
      let difference = if period.has_prefix("last") {
        -1
      } else if period.has_prefix("next") {
        1
      } else {
        0
      }
      if period.has_suffix("Week") {
        let start = -(today % 7).to_int() + difference * 7
        days(start, start + 7)
      } else {
        let (year, month, count) = if period.has_suffix("Month") {
          (year, month + difference, 1)
        } else if period.has_suffix("Quarter") {
          (year, (month - 1) / 3 * 3 + 1 + difference * 3, 3)
        } else {
          (year + difference, 1, 12)
        }
        (
          date_serial(year, month, 1, self.date1904).to_double(),
          date_serial(year, month + count, 1, self.date1904).to_double(),
        )
      }
    }
  }
}
