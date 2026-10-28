///|
pub(all) struct PageNumbering {
  start : Int64
  format : String
}

///|
pub impl ToJson for PageNumbering with fn to_json(self) {
  { "start": self.start.to_double(), "format": self.format }
}

///|
pub extend PageNumbering with ToJson::{to_json}

///|
pub fn PageNumbering::new(
  start~ : Int64 = 1L,
  format~ : String = "decimal",
) -> PageNumbering {
  { start, format, }
}

///|
pub fn PageNumbering::validate(
  self : PageNumbering,
) -> Unit raise @failure.Failure {
  guard self.start >= 0L &&
    self.start <= 4294967295L &&
    [
      "decimal", "decimalZero", "lowerLetter", "upperLetter", "lowerRoman", "upperRoman",
    ].contains(self.format) else {
    @failure.reject(
      "invalid-numbering", "Invalid page numbering start or format",
    )
  }
}

///|
pub fn PageNumbering::variant(
  self : PageNumbering,
  page : Int32,
  first : Bool,
  even : Bool,
) -> String {
  if page == 0 && first {
    "first"
  } else if (self.start + page.to_int64()) % 2L == 0L && even {
    "even"
  } else {
    "default"
  }
}

///|
pub fn PageNumbering::field_text(
  self : PageNumbering,
  field : String,
  page : Int32,
  total : Int32,
) -> String raise @failure.Failure {
  self.validate()
  let parts = field.split(":").to_array()
  guard parts.length() >= 1 &&
    parts.length() <= 2 &&
    ["PAGE", "NUMPAGES"].contains(parts[0].to_owned()) &&
    page >= 0 &&
    page < 1024 &&
    total >= 1 &&
    total <= 1024 else {
    @failure.reject(
      "unsupported-layout", "Unsupported running field or page number",
    )
  }
  let value = if parts[0] == "PAGE" {
    self.start + page.to_int64()
  } else {
    total.to_int64()
  }
  let format = if parts.length() == 2 {
    parts[1].to_owned()
  } else if parts[0] == "PAGE" {
    self.format
  } else {
    "decimal"
  }
  PageNumbering::{ start: 0L, format, }.validate()
  numbering_text(format, value)
}

///|
fn numbering_text(
  format : String,
  value : Int64,
) -> String raise @failure.Failure {
  match format {
    "decimal" => value.to_string()
    "decimalZero" => (if value < 10L { "0" } else { "" }) + value.to_string()
    _ =>
      numbering_value(
        format,
        if value == 0L {
          0
        } else {
          ((value - 1L) %
          (if format == "lowerLetter" || format == "upperLetter" {
            780L
          } else {
            32767L
          }) +
          1L).to_int()
        },
      )
  }
}
