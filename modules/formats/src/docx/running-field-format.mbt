///|
fn running_field_instruction(field : String) -> String raise @failure.Failure {
  let parts = field.split(":").to_array()
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
