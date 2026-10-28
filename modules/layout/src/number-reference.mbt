///|
pub(all) struct ParagraphNumbering {
  instance : Int32
  numeric : Bool
  values : Array[Int32]
  labels : Array[String?]
}

///|
pub impl ToJson for ParagraphNumbering with fn to_json(self) {
  {
    "instance": self.instance,
    "numeric": self.numeric,
    "values": self.values,
    "labels": self.labels.map(label => {
      label.map(value => Json(value)).unwrap_or(Json::null())
    }),
  }
}

///|
pub extend ParagraphNumbering with ToJson::{to_json}

///|
fn ParagraphNumbering::reference_text(
  self : ParagraphNumbering,
  mode : String,
  origin : ParagraphNumbering?,
  separator : String,
) -> String raise @failure.Failure {
  guard !self.values.is_empty() &&
    self.values.length() <= 9 &&
    self.labels.length() == self.values.length() else {
    @failure.reject("unsupported-layout", "number-reference-target-levels")
  }
  if !self.numeric {
    return "0"
  }
  let mut first = self.labels.length() - 1
  if mode == "numberFull" {
    first = 0
  } else if mode == "numberRelative" &&
    origin is Some(origin) &&
    origin.instance == self.instance {
    guard !origin.values.is_empty() && origin.values.length() <= 9 else {
      @failure.reject("unsupported-layout", "number-reference-origin-levels")
    }
    // ONLYOFFICE \r omits equal leading counters only within the same numbering instance.
    first = 0
    while first < self.values.length() &&
          first < origin.values.length() &&
          self.values[first] == origin.values[first] {
      first += 1
    }
  }
  let result = StringBuilder()
  for index in first..<self.labels.length() {
    let label = self.labels[index]
    guard label is Some(label) &&
      label.length() <= 256 &&
      label
      .iter()
      .all(c => c >= ' ' && c != '\u007f' && c != '\u2028' && c != '\u2029') else {
      @failure.reject("unsupported-layout", "number-reference-target-level")
    }
    result.write_string(label)
    if mode == "numberFull" && index + 1 < self.labels.length() {
      result.write_string(separator)
    }
  }
  result.to_string()
}
