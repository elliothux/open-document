///|
fn note_reference_code(instruction : String) -> String raise @failure.Failure {
  let tokens = text_reference_tokens(instruction)
  guard tokens.length() >= 2 && !tokens[0].1 && !tokens[1].1 else {
    @failure.reject("unsupported-layout", "Invalid note reference")
  }
  let options = ["NOTEREF", tokens[1].0]
  let mut merge = false
  for index = 2; index < tokens.length(); {
    guard !tokens[index].1 else {
      @failure.reject("unsupported-layout", "Quoted note reference switch")
    }
    match tokens[index].0.to_lower() {
      "\\h" => options.push("hyperlink")
      "\\p" => options.push("relative")
      "\\f" => options.push("superscript")
      "\\*" if !merge &&
        index + 1 < tokens.length() &&
        !tokens[index + 1].1 &&
        tokens[index + 1].0.to_upper() == "MERGEFORMAT" => {
        merge = true
        continue index + 2
      }
      _ =>
        @failure.reject(
          "unsupported-layout", "Unsupported note reference switch",
        )
    }
    continue index + 1
  }
  @layout.NoteReference::parse(options.join(":")).code()
}
