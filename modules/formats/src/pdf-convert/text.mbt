///|
fn numeric_text(text : String) -> Bool {
  if text.is_empty() || text.trim().to_owned() != text {
    return false
  }
  let value = if text.has_prefix("-") || text.has_prefix("+") {
    text[1:].to_owned()
  } else {
    text
  }
  let pieces = value.split(".").to_array()
  if pieces.length() > 2 ||
    pieces[0].is_empty() ||
    (pieces[0].length() > 1 && pieces[0].has_prefix("0")) {
    return false
  }
  let digits = pieces.join("")
  !digits.is_empty() &&
  digits.length() <= 15 &&
  digits.iter().all(c => c >= '0' && c <= '9') &&
  (pieces.length() == 1 || !pieces[1].is_empty())
}
