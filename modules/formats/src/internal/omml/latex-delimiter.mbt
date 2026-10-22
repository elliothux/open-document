///|
fn MathLatex::delimiter_boundary(self : MathLatex) -> Bool {
  ["middle", "right"].contains(self.peek_command())
}

///|
fn MathLatex::delimiter_char(self : MathLatex) -> String raise @failure.Failure {
  self.space()
  let ch = self.take()
  let value = if ch == '\\' {
    match self.command() {
      "lbrace" => "{"
      "rbrace" => "}"
      "langle" => "⟨"
      "rangle" => "⟩"
      "lfloor" => "⌊"
      "rfloor" => "⌋"
      "lceil" => "⌈"
      "rceil" => "⌉"
      "vert" | "lvert" | "rvert" => "|"
      "Vert" | "lVert" | "rVert" => "‖"
      "" =>
        match self.take() {
          '{' => "{"
          '}' => "}"
          '|' => "‖"
          _ => self.invalid()
        }
      _ => self.invalid()
    }
  } else if ch == '.' {
    ""
  } else if ch == '<' {
    "⟨"
  } else if ch == '>' {
    "⟩"
  } else {
    ch.to_string()
  }
  guard value.is_empty() ||
    (value.length() == 1 && "()[]{}|‖⌈⌉⌊⌋⟨⟩".contains(value)) else {
    self.invalid()
  }
  value
}

///|
fn MathLatex::delimiter(
  self : MathLatex,
  depth : Int,
) -> @layout.MathExpression raise @failure.Failure {
  let open = self.delimiter_char()
  let arguments : Array[@layout.MathExpression] = []
  let mut separator : String? = None
  for ;; {
    arguments.push(self.sequence(depth + 1, delimited=true))
    guard arguments.length() <= 64 else {
      @failure.reject("limit-exceeded", "Delimiter exceeds 64 arguments")
    }
    guard self.take() == '\\' else { self.invalid() }
    let boundary = self.command()
    guard boundary == "right" || boundary == "middle" else { self.invalid() }
    let value = self.delimiter_char()
    if boundary == "right" {
      return Delimited(
        open,
        value,
        separator.unwrap_or("|"),
        ReadOnlyArray::from_array(arguments),
      )
    }
    guard separator.map(before => before == value).unwrap_or(true) else {
      self.invalid()
    }
    separator = Some(value)
  }
}

///|
fn latex_delimiter(value : String) -> String {
  match value {
    "" => "."
    "{" => "\\{"
    "}" => "\\}"
    "‖" => "\\Vert "
    "⟨" => "\\langle "
    "⟩" => "\\rangle "
    "⌊" => "\\lfloor "
    "⌋" => "\\rfloor "
    "⌈" => "\\lceil "
    "⌉" => "\\rceil "
    _ => value
  }
}
