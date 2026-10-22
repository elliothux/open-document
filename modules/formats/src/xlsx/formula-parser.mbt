///|
priv struct FormulaAddress {
  address : Address
  fixed_row : Bool
  fixed_column : Bool
} derive(Eq)

///|
priv enum Expression {
  Constant(Value)
  Reference(String?, FormulaAddress, FormulaAddress?)
  Named(String?, String)
  Structured(String?, String)
  Unary(String, Expression)
  Binary(String, Expression, Expression)
  Function(String, Array[Expression])
} derive(Eq)

///|
priv enum Token {
  Word(String)
  Brackets(String)
  Numeric(Double, String)
  Quoted(String, Bool)
  ErrorLiteral(String)
  Operator(String)
  End
}

///|
priv struct FormulaParser {
  tokens : Array[Token]
  mut cursor : Int
}

///|
fn formula_tokens(
  text : String,
  spans? : Array[(Int, Int)],
) -> Array[Token] raise @failure.Failure {
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
    let token_start = index
    if character == '[' {
      index = structured_end(text, index)
      tokens.push(Brackets(text[token_start:index].to_owned()))
      if spans is Some(spans) {
        spans.push((token_start, index))
      }
      continue
    }
    if character == '#' {
      let errors = [
        "#REF!", "#DIV/0!", "#VALUE!", "#N/A", "#NAME?", "#NUM!", "#NULL!",
      ]
      guard errors.iter().find_first(value => text[index:].has_prefix(value))
        is Some(value) else {
        @failure.reject("unsupported-formula", "Unknown formula error literal")
      }
      index += value.length()
      tokens.push(ErrorLiteral(value))
      if spans is Some(spans) {
        spans.push((token_start, index))
      }
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
      if spans is Some(spans) {
        spans.push((token_start, index))
      }
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
      tokens.push(Numeric(value, text[start:index].to_owned()))
      if spans is Some(spans) {
        spans.push((token_start, index))
      }
      continue
    }
    let one = String::from_array([character])
    if [
        "+", "-", "*", "/", "&", "^", "%", "(", ")", ",", ":", "!", "=", "<", ">",
      ].contains(one) {
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
      if spans is Some(spans) {
        spans.push((token_start, index))
      }
      continue
    }
    guard character != '[' &&
      character != ']' &&
      character != '{' &&
      character != '}' &&
      character != ';' &&
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
    if spans is Some(spans) {
      spans.push((token_start, index))
    }
  }
  tokens.push(End)
  if spans is Some(spans) {
    spans.push((text.length(), text.length()))
  }
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
    @failure.reject("unsupported-formula", "Expected an A1 cell address")
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
  if !self.accept(":") {
    let first = formula_address(text) catch {
      @failure.Failure(code~, message~, part~, offset~) => {
        if name_identifier(text) {
          return Named(sheet, text)
        }
        raise @failure.Failure(code~, message~, part~, offset~)
      }
    }
    return Reference(sheet, first, None)
  }
  let endpoint = match self.take() {
    Word(text) | Numeric(_, text) => text
    _ => @failure.reject("formula-syntax", "Expected range endpoint")
  }
  let (first, last) = match (axis_reference(text), axis_reference(endpoint)) {
    (Some(Cell(first)), Some(Cell(last))) => (first, last)
    (Some(Row(first, a)), Some(Row(last, b))) =>
      (
        {
          address: { row: first, column: 1, },
          fixed_row: a,
          fixed_column: true,
        },
        {
          address: { row: last, column: 16384, },
          fixed_row: b,
          fixed_column: true,
        },
      )
    (Some(Column(first, a)), Some(Column(last, b))) =>
      (
        {
          address: { row: 1, column: first, },
          fixed_row: true,
          fixed_column: a,
        },
        {
          address: { row: 1048576, column: last, },
          fixed_row: true,
          fixed_column: b,
        },
      )
    _ => @failure.reject("formula-syntax", "Invalid or mixed range endpoints")
  }
  Reference(sheet, first, Some(last))
}

///|
fn FormulaParser::reference_token(
  self : FormulaParser,
) -> String raise @failure.Failure {
  match self.take() {
    Word(text) | Numeric(_, text) => text
    _ => @failure.reject("formula-syntax", "Expected worksheet reference")
  }
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
fn FormulaParser::atom(
  self : FormulaParser,
  depth : Int,
) -> Expression raise @failure.Failure {
  guard depth <= 64 else {
    @failure.reject("limit-exceeded", "Formula parser depth exceeded")
  }
  match self.take() {
    Numeric(value, text) =>
      if self.tokens[self.cursor] is Operator(":") {
        self.reference(None, text)
      } else {
        Constant(Number(value))
      }
    ErrorLiteral(value) => Constant(Error(value))
    Brackets(selector) => Structured(None, selector)
    Quoted(value, false) => Constant(Text(value))
    Quoted(sheet, true) => {
      guard self.accept("!") else {
        @failure.reject("formula-syntax", "Expected quoted worksheet reference")
      }
      self.reference(Some(sheet), self.reference_token())
    }
    Operator("+") => Unary("+", self.atom(depth + 1))
    Operator("-") => Unary("-", self.atom(depth + 1))
    Operator("(") => {
      let value = self.expression(1, depth + 1)
      guard self.accept(")") else {
        @failure.reject("formula-syntax", "Missing closing parenthesis")
      }
      value
    }
    Word(word) => {
      if self.tokens[self.cursor] is Brackets(selector) {
        self.cursor += 1
        guard name_identifier(word) else {
          @failure.reject("formula-syntax", "Invalid table name")
        }
        return Structured(Some(word), selector)
      }
      if self.accept("!") {
        return self.reference(Some(word), self.reference_token())
      }
      let upper = word.to_upper()
      let name = match upper {
        "_XLFN.IFNA" => "IFNA"
        "_XLFN.CONCAT" => "CONCAT"
        "_XLFN.TEXTJOIN" => "TEXTJOIN"
        "_XLFN.DAYS" => "DAYS"
        "_XLFN.XLOOKUP" => "XLOOKUP"
        "_XLFN.VAR.S" => "VAR.S"
        "_XLFN.VAR.P" => "VAR.P"
        "_XLFN.STDEV.S" => "STDEV.S"
        "_XLFN.STDEV.P" => "STDEV.P"
        "_XLFN.MODE.SNGL" => "MODE.SNGL"
        "_XLFN.MINIFS" => "MINIFS"
        "_XLFN.MAXIFS" => "MAXIFS"
        name => name
      }
      if self.accept("(") {
        let args : Array[Expression] = []
        if !self.accept(")") {
          for ;; {
            guard args.length() < 255 else {
              @failure.reject(
                "limit-exceeded", "Function argument budget exceeded",
              )
            }
            args.push(
              if self.tokens[self.cursor] is Operator(",") ||
                self.tokens[self.cursor] is Operator(")") {
                Constant(Blank)
              } else {
                self.expression(1, depth + 1)
              },
            )
            if self.accept(")") {
              break
            }
            guard self.accept(",") else {
              @failure.reject("formula-syntax", "Expected argument separator")
            }
            continue
          }
        }
        guard (match name {
          "IF" => args.length() == 2 || args.length() == 3
          "HYPERLINK" => args.length() == 1 || args.length() == 2
          "IFERROR"
          | "IFNA"
          | "MOD"
          | "ROUND"
          | "ROUNDUP"
          | "ROUNDDOWN"
          | "EXACT"
          | "POWER"
          | "REPT"
          | "LARGE"
          | "SMALL" => args.length() == 2
          "NOT" | "ISBLANK" | "ISNUMBER" | "ISTEXT" | "ABS" | "INT" | "SQRT" =>
            args.length() == 1
          "LEN" | "LOWER" | "UPPER" | "TRIM" => args.length() == 1
          "YEAR" | "MONTH" | "DAY" | "HOUR" | "MINUTE" | "SECOND" =>
            args.length() == 1
          "DATE" | "TIME" => args.length() == 3
          "DAYS" => args.length() == 2
          "ROW" | "COLUMN" => args.length() <= 1
          "ROWS" | "COLUMNS" => args.length() == 1
          "MATCH" => args.length() == 2 || args.length() == 3
          "INDEX" => args.length() >= 2 && args.length() <= 4
          "VLOOKUP" | "HLOOKUP" => args.length() == 3 || args.length() == 4
          "XLOOKUP" => args.length() >= 3 && args.length() <= 6
          "COUNTBLANK" => args.length() == 1
          "SUBTOTAL" => args.length() >= 2 && args.length() <= 255
          "COUNTIF" => args.length() == 2
          "COUNTIFS" =>
            args.length() >= 2 && args.length() <= 254 && args.length() % 2 == 0
          "SUMIF" | "AVERAGEIF" => args.length() == 2 || args.length() == 3
          "SUMIFS" | "AVERAGEIFS" | "MINIFS" | "MAXIFS" =>
            args.length() >= 3 && args.length() % 2 == 1
          "LEFT" | "RIGHT" => args.length() == 1 || args.length() == 2
          "MID" => args.length() == 3
          "FIND" | "SEARCH" => args.length() == 2 || args.length() == 3
          "SUBSTITUTE" => args.length() == 3 || args.length() == 4
          "CONCAT" => !args.is_empty() && args.length() <= 253
          "TEXTJOIN" => args.length() >= 3 && args.length() <= 254
          _ => !args.is_empty()
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
fn FormulaParser::primary(
  self : FormulaParser,
  depth : Int,
) -> Expression raise @failure.Failure {
  let mut value = self.atom(depth)
  while self.accept("%") {
    value = Unary("%", value)
  }
  value
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
      "&" => 2
      "+" | "-" => 3
      "*" | "/" => 4
      "^" => 5
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
