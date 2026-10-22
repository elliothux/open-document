///|
pub(all) enum MathExpression {
  Text(String)
  Row(ReadOnlyArray[MathExpression])
  Fraction(MathExpression, MathExpression)
  Scripts(MathExpression, MathExpression?, MathExpression?)
  Root(MathExpression?, MathExpression)
  Delimited(String, String, String, ReadOnlyArray[MathExpression])
  Nary(String, String, MathExpression?, MathExpression?, MathExpression)
  Matrix(
    String,
    ReadOnlyArray[String],
    ReadOnlyArray[ReadOnlyArray[MathExpression?]]
  )
}

///|
pub impl ToJson for MathExpression with fn to_json(self) {
  match self {
    Matrix(base, columns, rows) =>
      {
        "kind": "matrix",
        "baseAlignment": base,
        "columnAlignments": columns,
        "rows": rows.map(row => {
          row.map(value => {
            value.map(value => Json(value)).unwrap_or(Json::null())
          })
        }),
      }
    Nary(operator, limit_location, lower, upper, body) =>
      {
        "kind": "nary",
        "operator": operator,
        "limitLocation": limit_location,
        "lower": lower.map(value => Json(value)).unwrap_or(Json::null()),
        "upper": upper.map(value => Json(value)).unwrap_or(Json::null()),
        "body": body,
      }
    Delimited(open, close, separator, arguments) =>
      {
        "kind": "delimited",
        "open": open,
        "close": close,
        "separator": separator,
        "arguments": arguments,
      }
    Text(text) => { "kind": "text", "text": text }
    Row(children) => { "kind": "row", "children": children }
    Fraction(numerator, denominator) =>
      { "kind": "fraction", "numerator": numerator, "denominator": denominator }
    Root(degree, radicand) =>
      {
        "kind": "root",
        "degree": degree.map(value => Json(value)).unwrap_or(Json::null()),
        "radicand": radicand,
      }
    Scripts(base, subscript, superscript) =>
      {
        "kind": "scripts",
        "base": base,
        "subscript": subscript.map(value => Json(value)).unwrap_or(Json::null()),
        "superscript": superscript
        .map(value => Json(value))
        .unwrap_or(Json::null()),
      }
  }
}

///|
pub extend MathExpression with ToJson::{to_json}

///|
fn MathExpression::check(self : MathExpression) -> Unit raise @failure.Failure {
  let mut nodes = 0
  let mut units = 0
  fn visit(value : MathExpression, depth : Int) -> Unit raise @failure.Failure {
    nodes += 1
    guard depth <= 16 && nodes <= 256 else {
      @failure.reject("limit-exceeded", "Math exceeds depth 16 or 256 nodes")
    }
    match value {
      Matrix(base, columns, rows) => {
        guard ["top", "center", "bottom"].contains(base) &&
          columns.length() >= 1 &&
          columns.length() <= 64 &&
          columns
          .iter()
          .all(value => ["left", "center", "right"].contains(value)) &&
          rows.length() >= 1 &&
          rows.length() <= 64 &&
          rows.length() * columns.length() <= 256 &&
          rows.iter().all(row => row.length() == columns.length()) else {
          @failure.reject(
            "unsupported-math", "Matrix requires bounded rectangular rows and supported alignments",
          )
        }
        for row in rows {
          for cell in row {
            if cell is Some(value) {
              visit(value, depth + 1)
            } else {
              nodes += 1
              guard depth < 16 && nodes <= 256 else {
                @failure.reject(
                  "limit-exceeded", "Math exceeds depth 16 or 256 nodes",
                )
              }
            }
          }
        }
      }
      Nary(operator, location, lower, upper, body) => {
        guard operator.length() == 1 &&
          "∑∏∐∫∬∭∮∯∰⋃⋂⋁⋀".contains(operator) &&
          ["subSup", "undOvr"].contains(location) else {
          @failure.reject(
            "unsupported-math", "Unsupported n-ary operator or limit location",
          )
        }
        if lower is Some(value) {
          visit(value, depth + 1)
        }
        if upper is Some(value) {
          visit(value, depth + 1)
        }
        visit(body, depth + 1)
      }
      Delimited(open, close, separator, arguments) => {
        guard [open, close, separator].all(math_delimiter_character) &&
          arguments.length() >= 1 &&
          arguments.length() <= 64 else {
          @failure.reject(
            "unsupported-math", "Delimiter requires supported characters and one to 64 arguments",
          )
        }
        for argument in arguments {
          visit(argument, depth + 1)
        }
      }
      Text(text) => {
        units += text.length()
        guard units <= 4096 else {
          @failure.reject("limit-exceeded", "Math exceeds 4096 UTF-16 units")
        }
        guard !text.is_empty() &&
          text
          .iter()
          .all(ch => {
            ch.to_int() >= 32 &&
            (ch.to_int() < 0xd800 || ch.to_int() > 0xdfff) &&
            ch != '\u2028' &&
            ch != '\u2029' &&
            ch != '\ufffe' &&
            ch != '\uffff'
          }) else {
          @failure.reject(
            "unsupported-math", "Math requires nonempty single-line text",
          )
        }
      }
      Row(children) => {
        guard children.length() >= 2 else {
          @failure.reject(
            "unsupported-math", "Math row requires at least two children",
          )
        }
        guard children.length() <= 256 else {
          @failure.reject("limit-exceeded", "Math row exceeds 256 children")
        }
        for child in children {
          visit(child, depth + 1)
        }
      }
      Fraction(num, den) => {
        visit(num, depth + 1)
        visit(den, depth + 1)
      }
      Root(degree, radicand) => {
        if degree is Some(value) {
          visit(value, depth + 1)
        }
        visit(radicand, depth + 1)
      }
      Scripts(base, sub, sup) => {
        guard sub is Some(_) || sup is Some(_) else {
          @failure.reject("unsupported-math", "Math script requires an index")
        }
        visit(base, depth + 1)
        if sub is Some(value) {
          visit(value, depth + 1)
        }
        if sup is Some(value) {
          visit(value, depth + 1)
        }
      }
    }
  }
  visit(self, 0)
}

///|
pub fn MathExpression::linear_text(self : MathExpression) -> String {
  match self {
    Matrix(_, _, rows) =>
      "matrix(" +
      rows
      .map(row => {
        row
        .map(value => value.map(value => value.linear_text()).unwrap_or(""))
        .join(",")
      })
      .join(";") +
      ")"
    Nary(operator, _, lower, upper, body) =>
      operator +
      lower.map(value => "_(" + value.linear_text() + ")").unwrap_or("") +
      upper.map(value => "^(" + value.linear_text() + ")").unwrap_or("") +
      "(" +
      body.linear_text() +
      ")"
    Delimited(open, close, separator, arguments) =>
      open + arguments.map(value => value.linear_text()).join(separator) + close
    Text(text) => text
    Row(children) => children.map(child => child.linear_text()).join("")
    Fraction(num, den) =>
      "(" + num.linear_text() + ")/(" + den.linear_text() + ")"
    Root(degree, radicand) =>
      degree.map(value => "root[" + value.linear_text() + "]").unwrap_or("sqrt") +
      "(" +
      radicand.linear_text() +
      ")"
    Scripts(base, sub, sup) => {
      let base = match base {
        Text(text) => text
        _ => "(" + base.linear_text() + ")"
      }
      base +
      sub.map(value => "_(" + value.linear_text() + ")").unwrap_or("") +
      sup.map(value => "^(" + value.linear_text() + ")").unwrap_or("")
    }
  }
}

///|
pub struct MathFormula {
  expression : MathExpression
  style : TextStyle
  display : Bool
  ascent : Double
  primitives : Array[PositionedPrimitive]
}

///|
/// Mathematical structure and its uniform source style; layout derives child argument sizes.
pub fn MathFormula::new(
  expression : MathExpression,
  style : TextStyle,
  display~ : Bool = false,
) -> MathFormula {
  { expression, style, display, ascent: 0, primitives: [], }
}

///|
pub impl ToJson for MathFormula with fn to_json(self) {
  {
    "expression": self.expression,
    "style": self.style,
    "display": self.display,
  }
}

///|
pub extend MathFormula with ToJson::{to_json}

///|
fn MathFormula::validate(self : MathFormula) -> Unit raise @failure.Failure {
  self.expression.check()
  validate_math_style(self.style)
}

///|
fn MathFormula::copy(self : MathFormula) -> MathFormula {
  { ..self, primitives: self.primitives.copy(), }
}

///|
fn MathFormula::cache_units(self : MathFormula) -> Int {
  positioned_cache_units([self.expression.linear_text()], self.primitives)
}
