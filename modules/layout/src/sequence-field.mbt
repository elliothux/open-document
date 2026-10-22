///|
pub(all) struct SequenceField {
  sequence : String
  format : String
}

///|
pub fn SequenceField::parse(
  code : String,
) -> SequenceField raise @failure.Failure {
  let parts = code.split(":").to_array()
  guard (parts.length() == 2 || parts.length() == 3) &&
    parts[0] == "SEQ" &&
    !parts[1].is_empty() &&
    parts[1].length() <= 40 &&
    parts[1]
    .iter()
    .all(c => {
      c == '_' ||
      c.is_ascii_alphabetic() ||
      c.is_ascii_digit() ||
      (!c.is_ascii() && @ucd.non_ascii_id_continue.contains(c))
    }) &&
    parts[1]
    .get_char(0)
    .map(c => {
      c == '_' ||
      c.is_ascii_alphabetic() ||
      (!c.is_ascii() && @ucd.non_ascii_id_start.contains(c))
    })
    .unwrap_or(false) else {
    @failure.reject("unsupported-layout", "Invalid sequence field identifier")
  }
  let format = if parts.length() == 3 { parts[2].to_owned() } else { "" }
  guard [
    "", "decimal", "lowerLetter", "upperLetter", "lowerRoman", "upperRoman",
  ].contains(format) else {
    @failure.reject("unsupported-layout", "Invalid sequence field format")
  }
  { sequence: parts[1].to_owned(), format, }
}

///|
pub fn SequenceField::code(self : SequenceField) -> String {
  "SEQ:" +
  self.sequence +
  (if self.format.is_empty() { "" } else { ":" + self.format })
}

///|
fn SequenceField::text(
  self : SequenceField,
  value : Int,
) -> String raise @failure.Failure {
  PageNumbering::new(
    start=value.to_int64(),
    format=if self.format.is_empty() { "decimal" } else { self.format },
  ).field_text("PAGE", 0, 1)
}

///|
fn Flow::sequence_values(
  self : Flow,
) -> Map[(Int, Int), String] raise @failure.Failure {
  let counts : Map[String, Int] = Map([])
  let values : Map[(Int, Int), String] = Map([])
  for paragraph in self.body_field_paragraphs() {
    for span in paragraph.spans {
      if !span.field.has_prefix("SEQ:") {
        continue
      }
      let field = SequenceField::parse(span.field)
      let count = counts.get(field.sequence).unwrap_or(0) + 1
      guard values.length() < 4096 else {
        @failure.reject("limit-exceeded", "Sequence fields exceed limits")
      }
      counts[field.sequence] = count
      values[(paragraph.id, span.node)] = field.text(count)
    }
  }
  values
}
