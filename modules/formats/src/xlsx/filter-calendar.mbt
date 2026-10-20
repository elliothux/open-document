///|
fn filter_calendar_type(
  unit : String,
  value : Int,
) -> String raise @failure.Failure {
  guard (unit == "month" && value >= 1 && value <= 12) ||
    (unit == "quarter" && value >= 1 && value <= 4) else {
    @failure.reject(
      "invalid-operation", "Calendar filters require month 1..12 or quarter 1..4",
    )
  }
  "\{if unit == "month" { "M" } else { "Q" }}\{value}"
}

///|
fn read_calendar_filter(kind : String) -> FilterRule? {
  for value in 1..<=12 {
    if kind == "M\{value}" {
      return Some(Calendar("month", value))
    }
  }
  for value in 1..<=4 {
    if kind == "Q\{value}" {
      return Some(Calendar("quarter", value))
    }
  }
  None
}

///|
fn filter_calendar_matches(
  first : Int,
  last : Int,
  value : Double,
  work : FormulaWork,
) -> Bool raise @failure.Failure {
  if value.is_nan() ||
    value.is_inf() ||
    value < 0 ||
    value >= (if work.date1904 { 2957004 } else { 2958466 }) {
    return false
  }
  work.spend(amount=26)
  let (_, month, _) = date_parts(value.to_int(), work.date1904)
  month >= first && month <= last
}
