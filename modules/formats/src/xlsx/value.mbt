///|
pub(all) enum Value {
  Blank
  Text(String)
  Number(Double)
  Boolean(Bool)
  Error(String)
} derive(Eq)

///|
pub extend Value with Eq::{equal, not_equal}

///|
pub impl ToJson for Value with fn to_json(self) {
  match self {
    Blank => { "kind": "blank", "value": Json::null() }
    Text(value) => { "kind": "text", "value": value }
    Number(value) => { "kind": "number", "value": value }
    Boolean(value) => { "kind": "boolean", "value": value }
    Error(value) => { "kind": "error", "value": value }
  }
}

///|
pub extend Value with ToJson::{to_json}

///|
fn number(text : String) -> Double raise @failure.Failure {
  let value = @string.parse_double(text[:]) catch {
    _ => @failure.reject("malformed-xlsx", "Invalid numeric cell value")
  }
  guard !value.is_nan() && !value.is_inf() else {
    @failure.reject("malformed-xlsx", "Non-finite cell value")
  }
  value
}

///|
fn natural(text : String, limit : Int) -> Int raise @failure.Failure {
  guard !text.is_empty() && text.iter().all(c => c >= '0' && c <= '9') else {
    @failure.reject("malformed-xlsx", "Invalid nonnegative integer")
  }
  let value = @string.parse_int(text[:]) catch {
    _ => @failure.reject("malformed-xlsx", "Integer exceeds bounds")
  }
  guard value >= 0 && value <= limit else {
    @failure.reject("malformed-xlsx", "Integer exceeds bounds")
  }
  value
}

///|
fn Value::display(self : Value) -> String {
  match self {
    Blank => ""
    Text(text) | Error(text) => text
    Number(value) => if value == 0 { "0" } else { value.to_string() }
    Boolean(value) => if value { "TRUE" } else { "FALSE" }
  }
}

///|
fn input_value(text : String, literal~ : Bool) -> Value raise @failure.Failure {
  guard text.length() <= 32767 && @xml.valid_text(text) else {
    @failure.reject(
      "limit-exceeded", "Cell text is invalid or exceeds 32767 UTF-16 units",
    )
  }
  if text.is_empty() {
    return Blank
  }
  if literal {
    return Text(text)
  }
  if text.has_prefix("'") {
    return Text(text[1:].to_owned())
  }
  match text.to_upper() {
    "TRUE" => return Boolean(true)
    "FALSE" => return Boolean(false)
    _ => ()
  }
  let trimmed = text.trim().to_owned()
  let value = @string.parse_double(trimmed[:]) catch { _ => return Text(text) }
  if value.is_nan() || value.is_inf() {
    return Text(text)
  }
  Number(value)
}
