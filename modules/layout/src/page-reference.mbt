///|
pub(all) struct PageReference {
  bookmark : String
  format : String
  hyperlink : Bool
  relative : Bool
}

///|
pub fn PageReference::parse(
  code : String,
) -> PageReference raise @failure.Failure {
  let parts = code.split(":").to_array()
  guard parts.length() >= 2 &&
    parts.length() <= 5 &&
    parts[0] == "PAGEREF" &&
    !parts[1].is_empty() &&
    parts[1].length() <= 40 &&
    parts[1]
    .iter()
    .all(c => {
      c == '_' ||
      (c >= 'A' && c <= 'Z') ||
      (c >= 'a' && c <= 'z') ||
      (c >= '0' && c <= '9')
    }) &&
    !(parts[1][0] >= 48 && parts[1][0] <= 57) else {
    @failure.reject("unsupported-layout", "Invalid page reference target")
  }
  let mut format = ""
  let mut hyperlink = false
  let mut relative = false
  for option in parts[2:] {
    match option {
      "hyperlink" if !hyperlink => hyperlink = true
      "relative" if !relative => relative = true
      "decimal"
      | "decimalZero"
      | "lowerLetter"
      | "upperLetter"
      | "lowerRoman"
      | "upperRoman" if format.is_empty() => format = option.to_owned()
      _ =>
        @failure.reject("unsupported-layout", "Invalid page reference option")
    }
  }
  { bookmark: parts[1].to_owned(), format, hyperlink, relative, }
}

///|
pub fn PageReference::code(self : PageReference) -> String {
  "PAGEREF:" +
  self.bookmark +
  (if self.format.is_empty() { "" } else { ":" + self.format }) +
  (if self.hyperlink { ":hyperlink" } else { "" }) +
  (if self.relative { ":relative" } else { "" })
}

///|
fn PageReference::page_code(self : PageReference) -> String {
  "PAGE" + (if self.format.is_empty() { "" } else { ":" + self.format })
}

///|
fn PageReference::text(
  self : PageReference,
  numbering : PageNumbering,
  origin : Hit?,
  target : Hit?,
  total : Int32,
) -> String raise @failure.Failure {
  guard target is Some(target) else { return "Error! Bookmark not defined." }
  if !self.relative {
    return numbering.field_text(self.page_code(), target.page, total)
  }
  guard origin is Some(origin) else { return "below" }
  if origin.page != target.page {
    return "on page " + (target.page + 1).to_string()
  }
  // ONLYOFFICE compares physical caret coordinates with a 0.001 mm vertical tolerance.
  if (origin.y - target.y).abs() < 72.0 / 25400 {
    if target.x < origin.x {
      "above"
    } else {
      "below"
    }
  } else if target.y < origin.y {
    "above"
  } else {
    "below"
  }
}
