///|
fn running_field_instruction(field : String) -> String raise @failure.Failure {
  let parts = field.split(":").to_array()
  if parts[0] == "REF" {
    let reference = @layout.TextReference::parse(field) catch {
      @failure.Failure(..) =>
        @failure.reject("invalid-operation", "Invalid text reference options")
    }
    return "REF " +
      reference.bookmark +
      (if reference.hyperlink { " \\h" } else { "" }) +
      " \\* MERGEFORMAT"
  }
  if parts[0] == "SEQ" {
    let sequence = @layout.SequenceField::parse(field) catch {
      @failure.Failure(..) =>
        @failure.reject("invalid-operation", "Invalid sequence field options")
    }
    let page = running_field_instruction(
      "PAGE" +
      (if sequence.format.is_empty() { "" } else { ":" + sequence.format }),
    )
    return "SEQ " +
      sequence.sequence +
      page[4:].to_owned() +
      (if sequence.repeat {
        " \\c"
      } else {
        sequence.restart.map(n => " \\r " + n.to_string()).unwrap_or("")
      }) +
      sequence.headingLevel.map(n => " \\s " + n.to_string()).unwrap_or("") +
      (if sequence.hidden { " \\h" } else { "" })
  }
  if parts[0] == "PAGEREF" {
    let reference = @layout.PageReference::parse(field) catch {
      @failure.Failure(..) =>
        @failure.reject("invalid-operation", "Invalid page reference options")
    }
    let page = running_field_instruction(
      "PAGE" +
      (if reference.format.is_empty() { "" } else { ":" + reference.format }),
    )
    return "PAGEREF " +
      reference.bookmark +
      page[4:].to_owned() +
      (if reference.hyperlink { " \\h" } else { "" }) +
      (if reference.relative { " \\p" } else { "" })
  }
  guard parts.length() >= 1 &&
    parts.length() <= 2 &&
    ["PAGE", "NUMPAGES"].contains(parts[0].to_owned()) else {
    @failure.reject("invalid-operation", "Invalid running field")
  }
  if parts.length() == 1 {
    return field
  }
  let switch = match parts[1].to_owned() {
    "decimal" => "Arabic"
    "lowerLetter" => "alphabetic"
    "upperLetter" => "ALPHABETIC"
    "lowerRoman" => "roman"
    "upperRoman" => "ROMAN"
    _ =>
      @failure.reject(
        "invalid-operation", "Invalid explicit running field format",
      )
  }
  parts[0].to_owned() + " \\* " + switch
}
