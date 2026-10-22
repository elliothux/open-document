///|
let conditional_date_periods : ReadOnlyArray[String] = [
  "yesterday", "today", "tomorrow", "last7Days", "lastWeek", "thisWeek", "nextWeek",
  "lastMonth", "thisMonth", "nextMonth",
]

///|
fn Session::conditional_date_interval(
  self : Session,
  period : String,
) -> (Double, Double) raise @failure.Failure {
  guard conditional_date_periods.contains(period) else {
    @failure.reject("invalid-operation", "Unknown conditional date period")
  }
  if period == "last7Days" {
    let (_, end) = self.relative_filter_interval("today")
    let (year, month, day) = self.calendar_date.unwrap()
    let first = serial_from_ordinal(
      calendar_ordinal(year, month, day) - 6,
      self.date1904,
    )
    return (first.to_double(), end)
  }
  self.relative_filter_interval(period)
}

///|
fn conditional_date_value(
  value : Value,
  work : FormulaWork,
) -> Double? raise @failure.Failure {
  if value is Number(number) {
    return Some(number)
  }
  guard value is Text(text) else { return None }
  work.spend(amount=text.length())
  let text = text.trim()
  let mut index = 0
  if text.has_prefix("+") || text.has_prefix("-") {
    index += 1
  }
  let mut digits = 0
  while index < text.length() && text[index] >= 48 && text[index] <= 57 {
    index += 1
    digits += 1
  }
  if index < text.length() && text[index] == '.' {
    index += 1
    while index < text.length() && text[index] >= 48 && text[index] <= 57 {
      index += 1
      digits += 1
    }
  }
  guard digits > 0 else { return None }
  let end = index
  if index < text.length() && (text[index] == 'e' || text[index] == 'E') {
    index += 1
    if index < text.length() && (text[index] == '+' || text[index] == '-') {
      index += 1
    }
    let exponent = index
    while index < text.length() && text[index] >= 48 && text[index] <= 57 {
      index += 1
    }
    if index == exponent {
      index = end
    }
  }
  // ONLYOFFICE uses parseFloat on unformatted logical text, including numeric prefixes.
  let number = @string.parse_double(text[:index]) catch { _ => return None }
  if number.is_inf() || number.is_nan() {
    None
  } else {
    Some(number)
  }
}

///|
fn conditional_date_formula(
  period : String,
  anchor : Address,
) -> String raise @failure.Failure {
  let cell = anchor.name()
  let day = "FLOOR(\{cell},1)"
  let rounded = "ROUNDDOWN(\{cell},0)"
  match period {
    "yesterday" => "\{day}=TODAY()-1"
    "today" => "\{day}=TODAY()"
    "tomorrow" => "\{day}=TODAY()+1"
    "last7Days" => "AND(TODAY()-\{day}<=6,\{day}<=TODAY())"
    "lastWeek" =>
      "AND(TODAY()-\{rounded}>=WEEKDAY(TODAY()),TODAY()-\{rounded}<WEEKDAY(TODAY())+7)"
    "thisWeek" =>
      "AND(TODAY()-\{rounded}<=WEEKDAY(TODAY())-1,\{rounded}-TODAY()<=7-WEEKDAY(TODAY()))"
    "nextWeek" =>
      "AND(\{rounded}-TODAY()>7-WEEKDAY(TODAY()),\{rounded}-TODAY()<15-WEEKDAY(TODAY()))"
    "lastMonth" =>
      "AND(MONTH(\{cell})=MONTH(EDATE(TODAY(),-1)),YEAR(\{cell})=YEAR(EDATE(TODAY(),-1)))"
    "thisMonth" =>
      "AND(MONTH(\{cell})=MONTH(TODAY()),YEAR(\{cell})=YEAR(TODAY()))"
    _ =>
      "AND(MONTH(\{cell})=MONTH(EDATE(TODAY(),1)),YEAR(\{cell})=YEAR(EDATE(TODAY(),1)))"
  }
}
