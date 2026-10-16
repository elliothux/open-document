///|
fn supported_format(format : String) -> Bool {
  [
    "General", "@", "0", "0.00", "#,##0", "#,##0.00", "0%", "0.00%", "yyyy-mm-dd",
    "mm-dd-yy", "d-mmm-yy", "d-mmm", "mmm-yy", "h:mm AM/PM", "h:mm:ss AM/PM", "h:mm",
    "hh:mm:ss", "m/d/yy h:mm",
  ].contains(format)
}

///|
fn padded(value : Int, length : Int) -> String {
  let text = value.to_string()
  "0".repeat((length - text.length()).max(0)) + text
}

///|
fn decimal(value : Double, places : Int, grouped : Bool) -> String {
  if value.is_inf() {
    return "########"
  }
  let factor = if places == 2 { 100.0 } else { 1.0 }
  let scaled = (value.abs() * factor).round()
  if scaled > 9007199254740991.0 {
    return value.to_string()
  }
  let integer = (scaled / factor).floor().to_int64().to_string()
  let whole = StringBuilder()
  for i in 0..<integer.length() {
    if grouped && i > 0 && (integer.length() - i) % 3 == 0 {
      whole.write_char(',')
    }
    whole.write_char(integer.get_char(i).unwrap())
  }
  (if value < 0 && scaled != 0 { "-" } else { "" }) +
  whole.to_string() +
  (if places == 2 { "." + padded((scaled % 100).to_int(), 2) } else { "" })
}

///|
fn formatted(value : Value, format : String, date1904 : Bool) -> String {
  guard value is Number(value) && supported_format(format) else {
    return value.display()
  }
  match format {
    "General" | "@" => Number(value).display()
    "0" | "#,##0" => decimal(value, 0, format == "#,##0")
    "0.00" | "#,##0.00" => decimal(value, 2, format == "#,##0.00")
    "0%" | "0.00%" =>
      decimal(value * 100, if format == "0%" { 0 } else { 2 }, false) + "%"
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
      let month_name = [
          "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov",
          "Dec",
        ][month - 1]
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
