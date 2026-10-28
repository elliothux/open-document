///|
let math_nary_commands : Map[String, String] = {
  "sum": "∑",
  "prod": "∏",
  "coprod": "∐",
  "int": "∫",
  "iint": "∬",
  "iiint": "∭",
  "oint": "∮",
  "oiint": "∯",
  "oiiint": "∰",
  "bigcup": "⋃",
  "bigcap": "⋂",
  "bigvee": "⋁",
  "bigwedge": "⋀",
}

///|
fn MathLatex::nary(
  self : MathLatex,
  operator : String,
  depth : Int32,
) -> @layout.MathExpression raise @failure.Failure {
  let mut location = if "∫∬∭∮∯∰".contains(operator) {
    "subSup"
  } else {
    "undOvr"
  }
  self.space()
  if self.chars.get(self.offset) == Some('\\') {
    let start = self.offset
    ignore(self.take())
    match self.command() {
      "limits" => location = "undOvr"
      "nolimits" => location = "subSup"
      _ => self.offset = start
    }
  }
  let (lower, upper) = self.indices(depth)
  let body = self.scripted(depth + 1)
  Nary(operator, location, lower, upper, body)
}

///|
fn latex_nary(
  operator : String,
  location : String,
  lower : @layout.MathExpression?,
  upper : @layout.MathExpression?,
  body : @layout.MathExpression,
) -> String {
  let name = math_nary_commands
    .iter()
    .find_first(entry => entry.1 == operator)
    .unwrap().0
  "\\" +
  name +
  (if location == "undOvr" { "\\limits" } else { "\\nolimits" }) +
  lower.map(value => "_{" + latex(value) + "}").unwrap_or("") +
  upper.map(value => "^{" + latex(value) + "}").unwrap_or("") +
  "{" +
  latex(body) +
  "}"
}
