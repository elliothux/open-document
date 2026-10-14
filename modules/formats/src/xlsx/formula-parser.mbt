///|
priv struct FormulaAddress {
  address : Address
  fixed_row : Bool
  fixed_column : Bool
}

///|
priv enum Expression {
  Constant(Value)
  Reference(String?, FormulaAddress, FormulaAddress?)
  Unary(String, Expression)
  Binary(String, Expression, Expression)
  Function(String, Array[Expression])
}

///|
priv enum Token {
  Word(String)
  Numeric(Double)
  Quoted(String, Bool)
  Operator(String)
  End
}

///|
priv struct FormulaParser {
  tokens : Array[Token]
  mut cursor : Int
}

///|
fn formula_tokens(text : String) -> Array[Token] raise @failure.Failure {
  guard text.length() <= 8192 else {
    @failure.reject("limit-exceeded", "Formula source exceeds budget")
  }
  let tokens : Array[Token] = []
  let mut index = 0
  while index < text.length() {
    guard tokens.length() < 4096 else {
      @failure.reject("limit-exceeded", "Formula token budget exceeded")
    }
    let character = text.get_char(index).unwrap()
    if character.is_whitespace() {
      index += if character.to_int() > 0xffff { 2 } else { 1 }
      continue
    }
    if character == '"' || character == '\'' {
      let quote = character
      index += 1
      let output = StringBuilder()
      let mut closed = false
      while index < text.length() {
        let character = text.get_char(index).unwrap()
        index += if character.to_int() > 0xffff { 2 } else { 1 }
        if character == quote {
          if index < text.length() && text[index].to_int() == quote.to_int() {
            output.write_char(quote)
            index += 1
          } else {
            closed = true
            break
          }
        } else {
          output.write_char(character)
        }
      }
      guard closed else {
        @failure.reject(
          "formula-syntax", "Unterminated formula string or sheet name",
        )
      }
      tokens.push(Quoted(output.to_string(), quote == '\''))
      continue
    }
    if (character >= '0' && character <= '9') ||
      (
        character == '.' &&
        index + 1 < text.length() &&
        text[index + 1] >= 48 &&
        text[index + 1] <= 57
      ) {
      let start = index
      while index < text.length() &&
            ((text[index] >= 48 && text[index] <= 57) || text[index] == 46) {
        index += 1
      }
      if index < text.length() && (text[index] == 69 || text[index] == 101) {
        index += 1
        if index < text.length() && (text[index] == 43 || text[index] == 45) {
          index += 1
        }
        while index < text.length() && text[index] >= 48 && text[index] <= 57 {
          index += 1
        }
      }
      let value = @string.parse_double(text[start:index]) catch {
        _ => @failure.reject("formula-syntax", "Invalid numeric constant")
      }
      guard !value.is_inf() && !value.is_nan() else {
        @failure.reject("formula-syntax", "Non-finite numeric constant")
      }
      tokens.push(Numeric(value))
      continue
    }
    let one = String::from_array([character])
    if ["+", "-", "*", "/", "(", ")", ",", ":", "!", "=", "<", ">"].contains(
        one,
      ) {
      let mut operator = one
      index += 1
      if index < text.length() &&
        (
          (one == "<" && text[index] == 62) ||
          ((one == "<" || one == ">") && text[index] == 61)
        ) {
        operator += String::from_array([text[index].to_char().unwrap()])
        index += 1
      }
      tokens.push(Operator(operator))
      continue
    }
    guard character != '[' &&
      character != ']' &&
      character != '{' &&
      character != '}' &&
      character != ';' &&
      character != '%' &&
      character != '^' &&
      character != '&' &&
      character != '#' else {
      @failure.reject("unsupported-formula", "Unsupported formula syntax")
    }
    let start = index
    while index < text.length() {
      let character = text.get_char(index).unwrap()
      if character.is_whitespace() ||
        "+-*/(),:!=<>\"'[]{};%^&#".contains(String::from_array([character])) {
        break
      }
      index += if character.to_int() > 0xffff { 2 } else { 1 }
    }
    guard index > start else {
      @failure.reject("formula-syntax", "Invalid formula token")
    }
    tokens.push(Word(text[start:index].to_owned()))
  }
  tokens.push(End)
  tokens
}

///|
fn formula_address(text : String) -> FormulaAddress raise @failure.Failure {
  let mut index = 0
  let fixed_column = text.has_prefix("$")
  if fixed_column {
    index += 1
  }
  let start = index
  while index < text.length() &&
        (
          (text[index] >= 65 && text[index] <= 90) ||
          (text[index] >= 97 && text[index] <= 122)
        ) {
    index += 1
  }
  guard index > start else {
    @failure.reject("unsupported-formula", "Named references are unsupported")
  }
  let letters = text[start:index].to_upper().to_owned()
  let fixed_row = index < text.length() && text[index] == 36
  if fixed_row {
    index += 1
  }
  let address = Address::parse(letters + text[index:].to_owned())
  { address, fixed_row, fixed_column, }
}

///|
fn FormulaParser::take(self : FormulaParser) -> Token {
  let token = self.tokens[self.cursor]
  if !(token is End) {
    self.cursor += 1
  }
  token
}

///|
fn FormulaParser::accept(self : FormulaParser, value : String) -> Bool {
  if self.tokens[self.cursor] is Operator(actual) && actual == value {
    self.cursor += 1
    true
  } else {
    false
  }
}

///|
fn FormulaParser::reference(
  self : FormulaParser,
  sheet : String?,
  text : String,
) -> Expression raise @failure.Failure {
  let first = formula_address(text)
  let last = if self.accept(":") {
    guard self.take() is Word(text) else {
      @failure.reject("formula-syntax", "Expected range endpoint")
    }
    let last = formula_address(text)
    Some(last)
  } else {
    None
  }
  Reference(sheet, first, last)
}

///|
fn FormulaAddress::range(self : FormulaAddress, last : FormulaAddress) -> Range {
  {
    top: self.address.row.min(last.address.row),
    left: self.address.column.min(last.address.column),
    bottom: self.address.row.max(last.address.row),
    right: self.address.column.max(last.address.column),
  }
}

///|
fn FormulaParser::primary(
  self : FormulaParser,
  depth : Int,
) -> Expression raise @failure.Failure {
  guard depth <= 64 else {
    @failure.reject("limit-exceeded", "Formula parser depth exceeded")
  }
  match self.take() {
    Numeric(value) => Constant(Number(value))
    Quoted(value, false) => Constant(Text(value))
    Quoted(sheet, true) => {
      guard self.accept("!") && self.take() is Word(address) else {
        @failure.reject("formula-syntax", "Expected quoted worksheet reference")
      }
      self.reference(Some(sheet), address)
    }
    Operator("+") => Unary("+", self.primary(depth + 1))
    Operator("-") => Unary("-", self.primary(depth + 1))
    Operator("(") => {
      let value = self.expression(1, depth + 1)
      guard self.accept(")") else {
        @failure.reject("formula-syntax", "Missing closing parenthesis")
      }
      value
    }
    Word(word) => {
      if self.accept("!") {
        guard self.take() is Word(address) else {
          @failure.reject("formula-syntax", "Expected worksheet cell address")
        }
        return self.reference(Some(word), address)
      }
      let name = word.to_upper()
      if self.accept("(") {
        let args : Array[Expression] = []
        if !self.accept(")") {
          for ;; {
            guard args.length() < 255 else {
              @failure.reject(
                "limit-exceeded", "Function argument budget exceeded",
              )
            }
            args.push(self.expression(1, depth + 1))
            if self.accept(")") {
              break
            }
            guard self.accept(",") else {
              @failure.reject("formula-syntax", "Expected argument separator")
            }
            continue
          }
        }
        guard (if name == "IF" {
          args.length() == 2 || args.length() == 3
        } else {
          !args.is_empty()
        }) else {
          @failure.reject("formula-syntax", "Invalid function argument count")
        }
        Function(name, args)
      } else {
        match name {
          "TRUE" => Constant(Boolean(true))
          "FALSE" => Constant(Boolean(false))
          _ => self.reference(None, word)
        }
      }
    }
    _ => @failure.reject("formula-syntax", "Expected formula expression")
  }
}

///|
fn FormulaParser::expression(
  self : FormulaParser,
  minimum : Int,
  depth : Int,
) -> Expression raise @failure.Failure {
  let mut left = self.primary(depth)
  while self.tokens[self.cursor] is Operator(operator) {
    let precedence = match operator {
      "=" | "<>" | "<" | ">" | "<=" | ">=" => 1
      "+" | "-" => 2
      "*" | "/" => 3
      _ => 0
    }
    if precedence < minimum {
      break
    }
    ignore(self.take())
    let right = self.expression(precedence + 1, depth + 1)
    left = Binary(operator, left, right)
  }
  left
}

///|
fn parse_formula(text : String) -> Expression raise @failure.Failure {
  let parser = FormulaParser::{ tokens: formula_tokens(text), cursor: 0, }
  let result = parser.expression(1, 0)
  guard parser.take() is End else {
    @failure.reject(
      "unsupported-formula", "Unsupported trailing formula tokens",
    )
  }
  result
}
