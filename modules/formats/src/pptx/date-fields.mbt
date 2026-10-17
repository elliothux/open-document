///|
priv struct DateTime {
  value : String
  year : Int
  month : Int
  day : Int
  hour : Int
  minute : Int
  second : Int
}

///|
let date_field_text_reason = "Date fields are read-only"

///|
fn TextRun::has_date_source(self : TextRun) -> Bool {
  self.source
  .map(source => {
    source.node.uri == drawing_uri &&
    source.node.name == "fld" &&
    source.node
    .attribute("type")
    .unwrap_or("")
    .to_lower()
    .has_prefix("datetime")
  })
  .unwrap_or(false)
}

///|
fn calculated_field_reason(reason : String) -> Bool {
  [slide_number_text_reason, date_field_text_reason].contains(reason)
}

///|
fn read_date_time(value : String) -> DateTime raise @failure.Failure {
  // The existing validator checks the same Gregorian components without converting zones.
  guard value.length() == 19 else {
    @failure.reject("invalid-operation", "Invalid presentation date and time")
  }
  check_comment_date(value + "Z") catch {
    _ =>
      @failure.reject("invalid-operation", "Invalid presentation date and time")
  }
  {
    value,
    year: number(value[:4].to_owned(), 1, 9999).to_int(),
    month: number(value[5:7].to_owned(), 1, 12).to_int(),
    day: number(value[8:10].to_owned(), 1, 31).to_int(),
    hour: number(value[11:13].to_owned(), 0, 23).to_int(),
    minute: number(value[14:16].to_owned(), 0, 59).to_int(),
    second: number(value[17:19].to_owned(), 0, 59).to_int(),
  }
}

///|
fn date_digits(value : Int, count : Int) -> String {
  let text = value.to_string()
  "0".repeat((count - text.length()).max(0)) + text
}

///|
fn presentation_date_text(
  source : Ref,
  styles : Array[Ref],
  time : DateTime,
) -> String? {
  if !simple_text_field(source) {
    return None
  }
  let kind = source.node.attribute("type").unwrap_or("").to_lower()
  let kinds = [
    "datetime1", "datetime2", "datetime3", "datetime4", "datetime5", "datetime6",
    "datetime7", "datetime8", "datetime9", "datetime10", "datetime11", "datetime12",
    "datetime13",
  ]
  let kind = if kind == "datetimefigureout" { "datetime1" } else { kind }
  guard kinds.contains(kind) else { return None }
  let language = attribute(styles, "lang").unwrap_or("en-US").to_lower()
  guard ["en-us", "zh-cn", "zh-tw"].contains(language) else { return None }
  let y = date_digits(time.year, 4)
  let m = time.month.to_string()
  let d = time.day.to_string()
  let short_year = date_digits(time.year % 100, 2)
  let minutes = date_digits(time.minute, 2)
  let seconds = date_digits(time.second, 2)
  let hour12 = if time.hour % 12 == 0 { 12 } else { time.hour % 12 }
  let adjusted = time.year - (if time.month < 3 { 1 } else { 0 })
  let weekday = (
      adjusted +
      adjusted / 4 -
      adjusted / 100 +
      adjusted / 400 +
      [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4][time.month - 1] +
      time.day
    ) %
    7
  if language != "en-us" {
    let chinese = "\{y}年\{m}月\{d}日"
    let meridiem = if time.hour < 12 { "上午" } else { "下午" }
    let time12 = "\{date_digits(hour12, 2)}:\{minutes}"
    let date = "\{date_digits(time.month, 2)}/\{date_digits(time.day, 2)}/\{date_digits(time.year, 4)}"
    return Some(
      match kind {
        "datetime1" => "\{y}/\{m}/\{d}"
        "datetime2" | "datetime3" => chinese
        // ONLYOFFICE's Word-field parser keeps W literal in these zh locale patterns.
        "datetime4" | "datetime6" => chinese + "星期W"
        "datetime5" => "\{time.hour}时\{time.minute}分\{time.second}秒"
        "datetime7" => "\{y}年\{m}月"
        "datetime8" => "\{date} \{time12} \{meridiem}"
        "datetime9" => "\{date} \{time12}:\{seconds} \{meridiem}"
        "datetime10" => "\{date_digits(time.hour, 2)}:\{minutes}"
        "datetime11" => "\{date_digits(time.hour, 2)}:\{minutes}:\{seconds}"
        "datetime12" => "\{time12} \{meridiem}"
        _ => "\{time12}:\{seconds}: \{meridiem}"
      },
    )
  }
  let month = [
      "January", "February", "March", "April", "May", "June", "July", "August", "September",
      "October", "November", "December",
    ][time.month - 1]
  let day_name = [
      "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
    ][weekday]
  let short_month = month[:3].to_owned()
  let date = "\{m}/\{d}/\{y}"
  let time12 = "\{hour12}:\{minutes}"
  let meridiem = if time.hour < 12 { "AM" } else { "PM" }
  Some(
    match kind {
      "datetime1" => date
      "datetime2" => "\{day_name}, \{month} \{d}, \{y}"
      "datetime3" => "\{d} \{month} \{y}"
      "datetime4" => "\{month} \{d}, \{y}"
      "datetime5" => "\{d}-\{short_month}-\{short_year}"
      "datetime6" => "\{month} \{short_year}"
      "datetime7" => "\{short_month}-\{short_year}"
      "datetime8" => "\{date} \{time12} \{meridiem}"
      "datetime9" => "\{date} \{time12}:\{seconds} \{meridiem}"
      "datetime10" => "\{date_digits(time.hour, 2)}:\{minutes}"
      "datetime11" => "\{date_digits(time.hour, 2)}:\{minutes}:\{seconds}"
      "datetime12" => "\{time12} \{meridiem}"
      _ => "\{time12}:\{seconds} \{meridiem}"
    },
  )
}

///|
/// Refreshes derived date text without changing package source, revision or history.
pub fn Session::set_date_time(
  self : Session,
  revision : Int,
  value : String,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  self.check_idle()
  let time = read_date_time(value)
  if self.date_time.map(time => time.value) == Some(value) {
    return self.query()
  }
  let slides = self.slides.mapi((index, slide) => {
    let candidate = read_slide(
      self.opc,
      self.main,
      self.cache,
      slide.tree,
      index~,
      parts=self.parts,
      date_time=Some(time),
    )
    for object in candidate.objects {
      if object.paragraphs.any(p => p.runs.any(run => run.date_field)) {
        guard object.geometry is Some(geometry) else {
          @failure.reject("layout-overflow", "Missing date field geometry")
        }
        let (_, _, reason) = fit_text(object, geometry, probe, profile)
        guard reason.is_empty() else {
          @failure.reject("layout-overflow", reason)
        }
      }
    }
    candidate
  })
  self.validate_slides(self.main, slides)
  self.slides = slides
  self.date_time = Some(time)
  self.view = None
  self.query()
}
