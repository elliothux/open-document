///|
priv struct MathLatex {
  chars : Array[Char]
  mut offset : Int
  mut units : Int
}

///|
fn[T] MathLatex::invalid(self : MathLatex) -> T raise @failure.Failure {
  @failure.reject(
    "invalid-operation",
    "Unsupported or malformed LaTeX at character " + self.offset.to_string(),
  )
}

///|
fn MathLatex::space(self : MathLatex) -> Unit {
  while self.chars.get(self.offset) == Some(' ') {
    self.offset += 1
  }
}

///|
fn MathLatex::take(self : MathLatex) -> Char raise @failure.Failure {
  guard self.chars.get(self.offset) is Some(ch) else { self.invalid() }
  self.offset += 1
  ch
}

///|
fn MathLatex::text(
  self : MathLatex,
  value : String,
) -> @layout.MathExpression raise @failure.Failure {
  self.units += value.length()
  guard self.units <= 4096 else {
    @failure.reject("limit-exceeded", "Math exceeds 4096 UTF-16 units")
  }
  guard !value.is_empty() else { self.invalid() }
  Text(value)
}

///|
fn MathLatex::command(self : MathLatex) -> String raise @failure.Failure {
  let name = StringBuilder()
  while self.chars
        .get(self.offset)
        .map(ch => ch.is_ascii_alphabetic())
        .unwrap_or(false) {
    name.write_char(self.take())
  }
  name.to_string()
}

///|
fn MathLatex::peek_command(self : MathLatex) -> String {
  if self.chars.get(self.offset) != Some('\\') {
    return ""
  }
  let name = StringBuilder()
  let mut index = self.offset + 1
  while self.chars
        .get(index)
        .map(ch => ch.is_ascii_alphabetic())
        .unwrap_or(false) {
    name.write_char(self.chars[index])
    index += 1
  }
  name.to_string()
}

///|
fn MathLatex::literal(
  self : MathLatex,
) -> @layout.MathExpression raise @failure.Failure {
  self.space()
  guard self.take() == '{' else { self.invalid() }
  let value = StringBuilder()
  while self.chars.get(self.offset) != Some('}') {
    let ch = self.take()
    if ch == '\\' {
      let name = self.command()
      if name.is_empty() {
        let ch = self.take()
        guard "{}_ %$#&".contains(ch.to_string()) else { self.invalid() }
        value.write_char(ch)
      } else {
        let ch = match name {
          "textbackslash" => '\\'
          "textasciicircum" => '^'
          "textasciitilde" => '~'
          _ => self.invalid()
        }
        guard self.take() == '{' && self.take() == '}' else { self.invalid() }
        value.write_char(ch)
      }
    } else {
      guard !"{^~%$#&_".contains(ch.to_string()) else { self.invalid() }
      value.write_char(ch)
    }
  }
  ignore(self.take())
  self.text(value.to_string())
}

///|
fn MathLatex::group(
  self : MathLatex,
  depth : Int,
) -> @layout.MathExpression raise @failure.Failure {
  self.space()
  guard self.take() == '{' else { self.invalid() }
  let value = self.sequence(depth + 1)
  guard self.take() == '}' else { self.invalid() }
  value
}

///|
fn MathLatex::atom(
  self : MathLatex,
  depth : Int,
) -> @layout.MathExpression raise @failure.Failure {
  self.space()
  guard depth <= 64 else {
    @failure.reject("limit-exceeded", "LaTeX exceeds syntax depth 64")
  }
  if self.chars.get(self.offset) == Some('{') {
    return self.group(depth)
  }
  let ch = self.take()
  if ch == '\\' {
    let name = self.command()
    return match name {
      "begin" => self.matrix(depth)
      "left" => self.delimiter(depth)
      "frac" => Fraction(self.group(depth), self.group(depth))
      "sqrt" => {
        self.space()
        let degree = if self.chars.get(self.offset) == Some('[') {
          ignore(self.take())
          let degree = self.sequence(depth + 1, stop=']')
          guard self.take() == ']' else { self.invalid() }
          Some(degree)
        } else {
          None
        }
        Root(degree, self.group(depth))
      }
      "text" => self.literal()
      "backslash" => self.text("\\")
      "" => {
        let ch = self.take()
        guard "{}_ %$#&".contains(ch.to_string()) else { self.invalid() }
        self.text(ch.to_string())
      }
      _ =>
        if math_nary_commands.get(name) is Some(operator) {
          self.nary(operator, depth)
        } else {
          self.invalid()
        }
    }
  }
  guard !"}_^%$#&~".contains(ch.to_string()) else { self.invalid() }
  self.text(ch.to_string())
}

///|
fn MathLatex::indices(
  self : MathLatex,
  depth : Int,
) -> (@layout.MathExpression?, @layout.MathExpression?) raise @failure.Failure {
  let mut lower : @layout.MathExpression? = None
  let mut upper : @layout.MathExpression? = None
  self.space()
  while self.chars.get(self.offset) is Some('^' | '_') {
    let index = self.take()
    if index == '_' {
      guard lower is None else { self.invalid() }
      lower = Some(self.atom(depth + 1))
    } else {
      guard upper is None else { self.invalid() }
      upper = Some(self.atom(depth + 1))
    }
    self.space()
  }
  (lower, upper)
}

///|
fn MathLatex::scripted(
  self : MathLatex,
  depth : Int,
) -> @layout.MathExpression raise @failure.Failure {
  let base = self.atom(depth)
  let (lower, upper) = self.indices(depth)
  if lower is None && upper is None {
    base
  } else {
    Scripts(base, lower, upper)
  }
}

///|
fn MathLatex::sequence(
  self : MathLatex,
  depth : Int,
  stop~ : Char = '}',
  delimited~ : Bool = false,
  matrix~ : Bool = false,
) -> @layout.MathExpression raise @failure.Failure {
  let terms : Array[@layout.MathExpression] = []
  self.space()
  while self.offset < self.chars.length() &&
        self.chars.get(self.offset) != Some(stop) &&
        !(delimited && self.delimiter_boundary()) &&
        !(matrix && self.matrix_boundary()) {
    let term = self.scripted(depth)
    let children = match term {
      Row(children) => children.iter().collect()
      _ => [term]
    }
    for term in children {
      match (terms.last(), term) {
        (Some(Text(before)), Text(after)) =>
          terms[terms.length() - 1] = Text(before + after)
        _ => terms.push(term)
      }
    }
    guard terms.length() <= 256 else {
      @failure.reject("limit-exceeded", "LaTeX row exceeds 256 terms")
    }
    self.space()
  }
  match terms {
    [term] => term
    [] => self.invalid()
    _ => Row(ReadOnlyArray::from_array(terms))
  }
}

///|
fn parse_math_latex(
  source : String,
) -> @layout.MathExpression raise @failure.Failure {
  guard source.length() <= 131072 else {
    @failure.reject("limit-exceeded", "LaTeX exceeds 131072 UTF-16 units")
  }
  guard @xml.valid_text(source) &&
    source
    .iter()
    .all(ch => ch.to_int() >= 32 && ch != '\u2028' && ch != '\u2029') else {
    @failure.reject("invalid-operation", "LaTeX requires single-line text")
  }
  let parser : MathLatex = {
    chars: source.iter().collect(),
    offset: 0,
    units: 0,
  }
  let expression = parser.sequence(0)
  guard parser.offset == parser.chars.length() else { parser.invalid() }
  expression
}

///|
fn math_latex_text(text : String) -> String {
  let output = StringBuilder()
  for ch in text {
    output.write_string(
      match ch {
        '\\' => "\\textbackslash{}"
        '^' => "\\textasciicircum{}"
        '~' => "\\textasciitilde{}"
        '{' | '}' | '_' | '%' | '$' | '#' | '&' => "\\" + ch.to_string()
        _ => ch.to_string()
      },
    )
  }
  "\\text{" + output.to_string() + "}"
}

///|
fn math_latex(expression : @layout.MathExpression) -> String {
  match expression {
    Matrix(base, columns, rows) => math_latex_matrix(base, columns, rows)
    Nary(operator, location, lower, upper, body) =>
      math_latex_nary(operator, location, lower, upper, body)
    Delimited(open, close, separator, arguments) =>
      "\\left" +
      math_latex_delimiter(open) +
      arguments
      .map(math_latex)
      .join("\\middle" + math_latex_delimiter(separator)) +
      "\\right" +
      math_latex_delimiter(close)
    Root(degree, radicand) =>
      "\\sqrt" +
      degree.map(value => "[" + math_latex(value) + "]").unwrap_or("") +
      "{" +
      math_latex(radicand) +
      "}"
    Text(text) => math_latex_text(text)
    Row(children) => children.map(math_latex).join("")
    Fraction(num, den) =>
      "\\frac{" + math_latex(num) + "}{" + math_latex(den) + "}"
    Scripts(base, sub, sup) =>
      "{" +
      math_latex(base) +
      "}" +
      sub.map(value => "_{" + math_latex(value) + "}").unwrap_or("") +
      sup.map(value => "^{" + math_latex(value) + "}").unwrap_or("")
  }
}

///|
/// Create, replace or delete an inline expression using the supported bounded LaTeX syntax.
pub fn Session::edit_math(
  self : Session,
  revision : Int,
  action : String,
  id : Int,
  latex : String,
  probe~ : @layout.TextProbe,
  profile~ : Map[String, String],
  images~ : @layout.Images,
  format? : CharacterFormat,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let expression : @layout.MathExpression = if action == "delete" {
    Text("0")
  } else {
    parse_math_latex(latex)
  }
  self.edit_inline_math(
    revision,
    action,
    id,
    Math(
      @layout.MathFormula::new(
        expression,
        @layout.TextStyle::new("Cambria Math", 11, "000000"),
      ),
    ),
    plain=false,
    probe~,
    profile~,
    images~,
    format?,
  )
}
