///|
pub(all) struct PivotDateGroup {
  field : Int32
  units : Array[String]
} derive(ToJson)

///|
pub extend PivotDateGroup with ToJson::{to_json}

///|
let pivot_date_units : ReadOnlyArray[String] = [
  "years", "quarters", "months", "days",
]

///|
fn PivotDateGroup::validate(
  self : PivotDateGroup,
) -> Unit raise @failure.Failure {
  guard !self.units.is_empty() && self.units.length() <= 4 else {
    @failure.reject(
      "invalid-operation", "Unsupported pivot calendar group unit",
    )
  }
  let mut previous = -1
  for unit in self.units {
    let rank = pivot_date_units.search_by(item => item == unit).unwrap_or(-1)
    guard rank > previous else {
      @failure.reject(
        "invalid-operation", "Pivot calendar units require unique coarse-to-fine order",
      )
    }
    previous = rank
  }
}

///|
fn pivot_date_epoch(date1904 : Bool) -> Int64 {
  if date1904 {
    calendar_ordinal(1904, 1, 1)
  } else {
    calendar_ordinal(1899, 12, 30)
  }
}

///|
fn pivot_calendar_parts(
  value : Double,
  date1904 : Bool,
) -> (Int32, Int32, Int32) {
  let ordinal = pivot_date_epoch(date1904) + value.floor().to_int64()
  date_parts((ordinal - calendar_ordinal(1904, 1, 1)).to_int(), true)
}

///|
fn pivot_date_check(
  value : Double,
  date1904 : Bool,
) -> Unit raise @failure.Failure {
  guard !value.is_nan() &&
    !value.is_inf() &&
    value >= 0 &&
    value < (if date1904 { 2957004 } else { 2958466 }) else {
    @failure.reject(
      "protected-content", "Pivot dates are outside the workbook calendar",
    )
  }
}

///|
fn pivot_date_text(
  value : Double,
  date1904 : Bool,
) -> String raise @failure.Failure {
  pivot_date_check(value, date1904)
  let (year, month, day) = pivot_calendar_parts(value, date1904)
  let seconds = (value - value.floor()) * 86400
  let whole = seconds.floor().to_int()
  let fraction = seconds - whole.to_double()
  let digits = if fraction == 0 {
    ""
  } else {
    let parts = fraction.to_string().to_lower().split("e").collect()
    if parts.length() == 2 {
      let exponent = @string.parse_int(parts[1]) catch {
        _ => @failure.reject("invalid-operation", "Invalid pivot time fraction")
      }
      "." +
      "0".repeat((-exponent - 1).max(0)) +
      parts[0].replace_all(old=".", new="").to_owned()
    } else {
      "." + parts[0].split(".").collect()[1].to_owned()
    }
  }
  padded(year, 4) +
  "-" +
  padded(month, 2) +
  "-" +
  padded(day, 2) +
  "T" +
  padded(whole / 3600, 2) +
  ":" +
  padded(whole / 60 % 60, 2) +
  ":" +
  padded(whole % 60, 2) +
  digits
}

///|
fn pivot_date_parse(
  text : String,
  date1904 : Bool,
) -> Double raise @failure.Failure {
  let text = if text.has_suffix("Z") {
    text[:text.length() - 1].to_owned()
  } else {
    text
  }
  guard text.length() >= 19 && text.length() <= 350 else {
    @failure.reject("malformed-xlsx", "Invalid pivot date timestamp")
  }
  let p = filter_date_parts(text[:19].to_owned())
  guard p[2] <= calendar_months(p[0])[p[1] - 1] else {
    @failure.reject("malformed-xlsx", "Invalid native pivot date")
  }
  let fraction = if text.length() == 19 {
    0.0
  } else {
    let digits = text[20:].to_owned()
    guard text[19:20] == "." &&
      !digits.is_empty() &&
      digits.to_array().all(c => c >= '0' && c <= '9') else {
      @failure.reject("malformed-xlsx", "Invalid pivot date fraction")
    }
    number("0." + digits)
  }
  let value = (calendar_ordinal(p[0], p[1], p[2]) - pivot_date_epoch(date1904)).to_double() +
    ((p[3] * 3600 + p[4] * 60 + p[5]).to_double() + fraction) / 86400
  pivot_date_check(value, date1904)
  value
}

///|
fn pivot_date_cache_value(
  node : @xml.Node,
  date1904 : Bool,
) -> Value raise @failure.Failure {
  match node.name {
    "m" => Blank
    "d" => Number(pivot_date_parse(node.attribute("v").unwrap_or(""), date1904))
    _ =>
      @failure.reject(
        "protected-content", "Calendar pivot grouping requires native date items",
      )
  }
}

///|
fn pivot_calendar_label(value : Double, date1904 : Bool) -> String {
  formatted(Number(value), "mm-dd-yy", date1904)
}

///|
fn PivotDateGroup::build(
  self : PivotDateGroup,
  values : Array[Value],
  date1904 : Bool,
  unit? : String,
) -> PivotGroupItems raise @failure.Failure {
  self.validate()
  let unit = unit.unwrap_or(self.units[self.units.length() - 1])
  guard self.units.contains(unit) else {
    @failure.reject(
      "invalid-operation", "Pivot calendar component is unavailable",
    )
  }
  let mut start : Double? = None
  let mut end : Double? = None
  for value in values {
    match value {
      Number(value) => {
        pivot_date_check(value, date1904)
        start = Some(
          start.map(previous => previous.min(value)).unwrap_or(value),
        )
        end = Some(end.map(previous => previous.max(value)).unwrap_or(value))
      }
      Blank => ()
      _ =>
        @failure.reject(
          "protected-content", "Calendar pivot grouping requires date numbers or blanks",
        )
    }
  }
  let start = start.unwrap_or(0)
  let end = end.unwrap_or(0)
  let limit = if date1904 { 2957004.0 } else { 2958466.0 }
  let end = if end == end.floor() {
    if end + 1 < limit {
      end + 1
    } else {
      end + 86399.0 / 86400
    }
  } else {
    end
  }
  let (first_year, _, _) = pivot_calendar_parts(start, date1904)
  let (last_year, _, _) = pivot_calendar_parts(end, date1904)
  let first_year = if !date1904 && start < 2 { 1900 } else { first_year }
  let last_year = if !date1904 && end < 2 { 1900 } else { last_year }
  guard unit != "years" || last_year - first_year + 1 <= 4094 else {
    @failure.reject("limit-exceeded", "Pivot calendar years exceed budget")
  }
  let items : Array[Value] = [
    Text(
      if values.contains(Blank) {
        "(blank)"
      } else {
        "<" + pivot_calendar_label(start, date1904)
      },
    ),
  ]
  match unit {
    "years" =>
      for year in first_year..<=last_year {
        items.push(Text(year.to_string()))
      }
    "quarters" =>
      for quarter in 1..<=4 {
        items.push(Text("Qtr" + quarter.to_string()))
      }
    "months" =>
      for month in date_month_names {
        items.push(Text(month))
      }
    _ =>
      for day in 0..<366 {
        items.push(
          Text(
            formatted(
              Number(
                date_serial(2000, 1, 1, true).to_double() + day.to_double(),
              ),
              "d-mmm",
              true,
            ),
          ),
        )
      }
  }
  items.push(Text(">" + pivot_calendar_label(end, date1904)))
  let indices = values.map(value => {
    guard value is Number(value) else { return 0 }
    let (year, month, day) = pivot_calendar_parts(value, date1904)
    // Native calendar getters map the two 1899 epoch dates into January 1900.
    let native_year = if !date1904 && value < 2 { 1900 } else { year }
    let native_month = if !date1904 && value < 2 { 1 } else { month }
    match unit {
      "years" => native_year - first_year + 1
      "quarters" => (native_month - 1) / 3 + 1
      "months" => native_month
      _ =>
        if year == 1899 && month == 12 && day == 30 {
          0
        } else if year == 1899 && month == 12 && day == 31 {
          1
        } else {
          (calendar_ordinal(2000, month, day) - calendar_year_days(2000)).to_int() +
          (if year == 1900 && month <= 2 { 1 } else { 0 })
        }
    }
  })
  { settings: DateBuckets(self, unit~, start~, end~), items, indices, }
}
