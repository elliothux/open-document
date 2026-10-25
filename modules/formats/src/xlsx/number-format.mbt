///|
fn supported_format(format : String) -> Bool {
  [
    "General", "@", "0", "0.00", "#,##0", "#,##0.00", "0%", "0.00%", "yyyy-mm-dd",
    "mm-dd-yy", "d-mmm-yy", "d-mmm", "mmm-yy", "h:mm AM/PM", "h:mm:ss AM/PM", "h:mm",
    "hh:mm:ss", "m/d/yy h:mm", "0.0", "0.000", "0.0000", "#,##0.0", "#,##0.000",
    "#,##0.0000", "0.0%", "0.000%", "0.0000%", "$0.00", "$#,##0.00", "¥0.00", "¥#,##0.00",
  ].contains(format)
}

///|
fn padded(value : Int, length : Int) -> String {
  let text = value.to_string()
  "0".repeat((length - text.length()).max(0)) + text
}

///|
fn decimal(
  value : Double,
  places : Int,
  grouped : Bool,
  percent~ : Bool = false,
) -> String {
  if value.is_inf() || (percent && (value * 100).is_inf()) {
    return "########"
  }
  let factor = @math.pow(10, places.to_double())
  // Round the source decimal before percentage scaling so 0.10005 becomes 10.01%.
  let rounded = match
    rounded_decimal(
      value,
      (places + (if percent { 2 } else { 0 })).to_double(),
      "ROUND",
    ) {
    Number(value) => value
    _ => return "########"
  }
  let scaled = (rounded.abs() * factor * (if percent { 100 } else { 1 })).round()
  if scaled > 9007199254740991.0 {
    return (value * (if percent { 100 } else { 1 })).to_string()
  }
  let integer = (scaled / factor).floor().to_int64().to_string()
  let whole = StringBuilder()
  for i in 0..<integer.length() {
    if grouped && i > 0 && (integer.length() - i) % 3 == 0 {
      whole.write_char(',')
    }
    whole.write_char(integer.get_char(i).unwrap())
  }
  (if rounded < 0 && scaled != 0 { "-" } else { "" }) +
  whole.to_string() +
  (if places > 0 {
    "." + padded((scaled % factor).to_int(), places)
  } else {
    ""
  })
}

///|
fn formatted(value : Value, format : String, date1904 : Bool) -> String {
  guard value is Number(value) && supported_format(format) else {
    return value.display()
  }
  match format {
    "General" => general_number(value)
    "@" => Number(value).display()
    code if ["0", "#", "$", "¥"].any(prefix => code.has_prefix(prefix)) => {
      let percent = code.has_suffix("%")
      let places = code
        .split_once(".")
        .map(pair => pair.1.length() - (if percent { 1 } else { 0 }))
        .unwrap_or(0)
      let number = decimal(value, places, code.contains(","), percent~)
      let currency = if code.has_prefix("$") {
        "$"
      } else if code.has_prefix("¥") {
        "¥"
      } else {
        ""
      }
      (if number.has_prefix("-") {
        "-" + currency + number[1:].to_owned()
      } else {
        currency + number
      }) +
      (if percent { "%" } else { "" })
    }
    _ => {
      if value < 0 || value >= (if date1904 { 2957004 } else { 2958466 }) {
        return "########"
      }
      let day = value.floor().to_int()
      let (year, month, date) = date_parts(day, date1904)
      if year > 9999 {
        return "########"
      }
      let seconds = ((value - value.floor()) * 86400).round().to_int() % 86400
      let hour = seconds / 3600
      let time = padded(hour, 2) +
        ":" +
        padded(seconds / 60 % 60, 2) +
        ":" +
        padded(seconds % 60, 2)
      let short = padded(month, 2) +
        "-" +
        padded(date, 2) +
        "-" +
        padded(year % 100, 2)
      let month_name = date_month_names[month - 1]
      match format {
        "yyyy-mm-dd" =>
          padded(year, 4) + "-" + padded(month, 2) + "-" + padded(date, 2)
        "mm-dd-yy" => short
        "d-mmm-yy" => "\{date}-\{month_name}-\{padded(year % 100, 2)}"
        "d-mmm" => "\{date}-\{month_name}"
        "mmm-yy" => "\{month_name}-\{padded(year % 100, 2)}"
        "h:mm" => "\{hour}:\{padded(seconds / 60 % 60, 2)}"
        "h:mm AM/PM" | "h:mm:ss AM/PM" =>
          "\{if hour % 12 == 0 { 12 } else { hour % 12 }}:\{padded(seconds / 60 % 60, 2)}" +
          (if format == "h:mm:ss AM/PM" {
            ":" + padded(seconds % 60, 2)
          } else {
            ""
          }) +
          (if hour < 12 { " AM" } else { " PM" })
        "m/d/yy h:mm" =>
          "\{month}/\{date}/\{padded(year % 100, 2)} \{hour}:\{padded(seconds / 60 % 60, 2)}"
        _ => time
      }
    }
  }
}
