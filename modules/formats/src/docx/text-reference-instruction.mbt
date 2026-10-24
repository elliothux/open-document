///|
fn text_reference_tokens(
  instruction : String,
) -> Array[(String, Bool)] raise @failure.Failure {
  let tokens : Array[(String, Bool)] = []
  let mut index = 0
  while index < instruction.length() {
    if [32, 9].contains(instruction[index].to_int()) {
      index += 1
      continue
    }
    if instruction[index] != '"' {
      let start = index
      while index < instruction.length() &&
            ![32, 9].contains(instruction[index].to_int()) {
        guard instruction[index] != '"' else {
          @failure.reject(
            "unsupported-layout", "Invalid reference instruction quote",
          )
        }
        index += 1
      }
      tokens.push((instruction[start:index].to_owned(), false))
      continue
    }
    index += 1
    let output = StringBuilder()
    let mut start = index
    let mut closed = false
    while index < instruction.length() {
      if instruction[index] == '\\' &&
        index + 1 < instruction.length() &&
        instruction[index + 1] == '"' {
        output.write_string(instruction[start:index].to_owned())
        output.write_string("\"")
        index += 2
        start = index
      } else if instruction[index] == '"' {
        output.write_string(instruction[start:index].to_owned())
        index += 1
        closed = true
        break
      } else {
        index += 1
      }
    }
    guard closed &&
      (
        index == instruction.length() ||
        [32, 9].contains(instruction[index].to_int())
      ) else {
      @failure.reject(
        "unsupported-layout", "Unterminated reference instruction quote",
      )
    }
    tokens.push((output.to_string(), true))
  }
  tokens
}

///|
fn text_reference_code(instruction : String) -> String raise @failure.Failure {
  let tokens = text_reference_tokens(instruction)
  guard tokens.length() >= 2 && !tokens[0].1 && !tokens[1].1 else {
    @failure.reject("unsupported-layout", "Invalid text reference")
  }
  check_bookmark_name(tokens[1].0)
  let mut hyperlink = false
  let mut numbering = ""
  let mut relative = false
  let mut merge = false
  let mut separator = ""
  let mut delimiter = false
  for index = 2; index < tokens.length(); {
    guard !tokens[index].1 else {
      @failure.reject("unsupported-layout", "Quoted reference switch")
    }
    match tokens[index].0.to_lower() {
      "\\h" if !hyperlink => {
        hyperlink = true
        continue index + 1
      }
      "\\p" if !relative => {
        relative = true
        continue index + 1
      }
      "\\n" | "\\r" | "\\w" if numbering.is_empty() => {
        numbering = match tokens[index].0.to_lower() {
          "\\n" => "number"
          "\\r" => "numberRelative"
          _ => "numberFull"
        }
        continue index + 1
      }
      "\\d" if !delimiter && index + 1 < tokens.length() => {
        delimiter = true
        separator = tokens[index + 1].0
        continue index + 2
      }
      "\\*" if !merge &&
        index + 1 < tokens.length() &&
        !tokens[index + 1].1 &&
        tokens[index + 1].0.to_upper() == "MERGEFORMAT" => {
        merge = true
        continue index + 2
      }
      _ =>
        @failure.reject(
          "unsupported-layout", "Unsupported text reference switch",
        )
    }
  }
  guard merge || !numbering.is_empty() || relative else {
    @failure.reject(
      "unsupported-layout", "Text references require retained result formatting",
    )
  }
  let code = @layout.TextReference::{
    bookmark: tokens[1].0,
    hyperlink,
    numbering,
    relative,
    separator,
  }.code()
  ignore(@layout.TextReference::parse(code))
  code
}
