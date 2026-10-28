///|
fn MathLatex::matrix_name(self : MathLatex) -> String raise @failure.Failure {
  self.space()
  guard self.take() == '{' else { self.invalid() }
  let name = StringBuilder()
  let mut length = 0
  while self.chars.get(self.offset) != Some('}') {
    let ch = self.take()
    length += 1
    guard length <= 16 && ch.is_ascii_alphabetic() else { self.invalid() }
    name.write_char(ch)
  }
  ignore(self.take())
  name.to_string()
}

///|
fn MathLatex::matrix_boundary(self : MathLatex) -> Bool {
  self.chars.get(self.offset) == Some('&') ||
  (
    self.chars.get(self.offset) == Some('\\') &&
    self.chars.get(self.offset + 1) == Some('\\')
  ) ||
  self.peek_command() == "end"
}

///|
fn MathLatex::matrix(
  self : MathLatex,
  depth : Int32,
) -> @layout.MathExpression raise @failure.Failure {
  let name = self.matrix_name()
  guard [
    "matrix", "array", "pmatrix", "bmatrix", "Bmatrix", "vmatrix", "Vmatrix", "aligned",
    "gathered",
  ].contains(name) else {
    self.invalid()
  }
  let mut base = "center"
  let columns : Array[String] = []
  if ["array", "aligned", "gathered"].contains(name) {
    self.space()
    if self.chars.get(self.offset) == Some('[') {
      ignore(self.take())
      self.space()
      base = match self.take() {
        't' => "top"
        'c' => "center"
        'b' => "bottom"
        _ => self.invalid()
      }
      self.space()
      guard self.take() == ']' else { self.invalid() }
    }
  }
  if name == "array" {
    self.space()
    guard self.take() == '{' else { self.invalid() }
    while self.chars.get(self.offset) != Some('}') {
      let ch = self.take()
      if ch == ' ' {
        continue
      }
      columns.push(
        match ch {
          'l' => "left"
          'c' => "center"
          'r' => "right"
          _ => self.invalid()
        },
      )
      guard columns.length() <= 64 else {
        @failure.reject("limit-exceeded", "Matrix exceeds 64 columns")
      }
    }
    ignore(self.take())
    guard !columns.is_empty() else { self.invalid() }
  }
  let rows : Array[Array[@layout.MathExpression?]] = []
  let mut row : Array[@layout.MathExpression?] = []
  let mut cells = 0
  for ;; {
    self.space()
    if !row.is_empty() || rows.is_empty() || self.peek_command() != "end" {
      row.push(
        if self.matrix_boundary() {
          None
        } else {
          Some(self.sequence(depth + 1, matrix=true))
        },
      )
      cells += 1
      guard row.length() <= 64 && cells <= 256 else {
        @failure.reject("limit-exceeded", "Matrix exceeds row or cell budget")
      }
    }
    if self.chars.get(self.offset) == Some('&') {
      ignore(self.take())
      continue
    }
    if self.peek_command() == "end" {
      if !row.is_empty() {
        rows.push(row)
      }
      ignore(self.take())
      guard self.command() == "end" && self.matrix_name() == name else {
        self.invalid()
      }
      break
    }
    guard self.take() == '\\' && self.take() == '\\' else { self.invalid() }
    rows.push(row)
    row = []
    guard rows.length() <= 64 else {
      @failure.reject("limit-exceeded", "Matrix exceeds 64 rows")
    }
    self.space()
    guard self.chars.get(self.offset) != Some('[') else { self.invalid() }
  }
  if name == "array" && rows.iter().any(row => row.length() > columns.length()) {
    self.invalid()
  }
  if ["aligned", "gathered"].contains(name) {
    guard !rows.is_empty() &&
      rows.length() <= 64 &&
      (name != "gathered" || rows.iter().all(row => row.length() == 1)) else {
      self.invalid()
    }
    return EquationArray(
      base,
      ReadOnlyArray::from_array(rows.map(row => ReadOnlyArray::from_array(row))),
    )
  }
  let (columns, rows) = matrix_grid(columns, rows)
  let value : @layout.MathExpression = Matrix(base, columns, rows)
  let pair = match name {
    "pmatrix" => ("(", ")")
    "bmatrix" => ("[", "]")
    "Bmatrix" => ("{", "}")
    "vmatrix" => ("|", "|")
    "Vmatrix" => ("‖", "‖")
    _ => ("", "")
  }
  if pair.0.is_empty() {
    value
  } else {
    Delimited(pair.0, pair.1, "|", ReadOnlyArray::from_array([value]))
  }
}

///|
fn latex_matrix(
  base : String,
  columns : ReadOnlyArray[String],
  rows : ReadOnlyArray[ReadOnlyArray[@layout.MathExpression?]],
) -> String {
  let position = match base {
    "top" => "t"
    "bottom" => "b"
    _ => "c"
  }
  let columns = columns
    .map(value => {
      match value {
        "left" => "l"
        "right" => "r"
        _ => "c"
      }
    })
    .join("")
  "\\begin{array}[" +
  position +
  "]{" +
  columns +
  "}" +
  rows
  .map(row => row.map(value => value.map(latex).unwrap_or("")).join("&"))
  .join("\\\\") +
  "\\end{array}"
}
