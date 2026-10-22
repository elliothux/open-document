///|
fn conditional_text_kind(kind : String) -> Bool {
  ["containsText", "notContainsText", "beginsWith", "endsWith"].contains(kind)
}

///|
fn conditional_text_match(
  kind : String,
  text : String,
  value : Value,
  work : FormulaWork,
) -> Bool raise @failure.Failure {
  let actual = value.display()
  work.spend(amount=text.length() + actual.length())
  // ONLYOFFICE gives a Boolean search operand precedence over text matching.
  if logical_value(Text(text)) is Boolean(accepted) {
    return accepted
  }
  let matched = if value is Error(_) {
    false
  } else {
    let actual = actual.to_lower()
    let text = text.to_lower()
    match kind {
      "beginsWith" =>
        (value is Text(_) || text.is_empty()) && actual.has_prefix(text)
      "endsWith" =>
        (value is Text(_) || text.is_empty()) && actual.has_suffix(text)
      _ => !actual.is_empty() && actual.contains(text)
    }
  }
  if kind == "notContainsText" {
    !matched
  } else {
    matched
  }
}

///|
fn conditional_text_formula(
  kind : String,
  text : String,
  anchor : Address,
) -> String raise @failure.Failure {
  let quoted = (value : String) => {
    "\"" + value.replace_all(old="\"", new="\"\"") + "\""
  }
  let address = anchor.name()
  let literal = quoted(text)
  let formula = match kind {
    "beginsWith" => "LEFT(\{address},LEN(\{literal}))=\{literal}"
    "endsWith" => "RIGHT(\{address},LEN(\{literal}))=\{literal}"
    _ => {
      let escaped = text
        .replace_all(old="~", new="~~")
        .replace_all(old="*", new="~*")
        .replace_all(old="?", new="~?")
      let error = "ISERROR(SEARCH(\{quoted(escaped)},\{address}))"
      if kind == "containsText" {
        "NOT(\{error})"
      } else {
        error
      }
    }
  }
  guard formula.length() <= 8192 else {
    @failure.reject("limit-exceeded", "Conditional text formula exceeds budget")
  }
  formula
}
