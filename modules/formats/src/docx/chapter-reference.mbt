///|
fn chapter_reference_code(
  instruction : String,
) -> String raise @failure.Failure {
  let tokens = text_reference_tokens(instruction)
  guard tokens.length() >= 3 &&
    tokens[0].0.to_upper() == "STYLEREF" &&
    !tokens[0].1 &&
    tokens[1].0.length() == 1 &&
    tokens[1].0[0] >= '1' &&
    tokens[1].0[0] <= '9' else {
    @failure.reject(
      "unsupported-layout", "Chapter references require an outline level",
    )
  }
  let mut number = false
  let mut merge = false
  for i = 2; i < tokens.length(); {
    guard !tokens[i].1 else {
      @failure.reject("unsupported-layout", "Invalid chapter reference switch")
    }
    if tokens[i].0.to_lower() == "\\s" && !number {
      number = true
      continue i + 1
    }
    guard tokens[i].0 == "\\*" &&
      i + 1 < tokens.length() &&
      tokens[i + 1].0.to_upper() == "MERGEFORMAT" &&
      !tokens[i + 1].1 &&
      !merge else {
      @failure.reject(
        "unsupported-layout", "Unsupported chapter reference switch",
      )
    }
    merge = true
    continue i + 2
  }
  guard number else {
    @failure.reject(
      "unsupported-layout", "Chapter references require the number switch",
    )
  }
  "STYLEREF:" + tokens[1].0
}
