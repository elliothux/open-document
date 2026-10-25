///|
fn stored_formula_names(formula : String) -> String raise @failure.Failure {
  let spans : Array[(Int, Int)] = []
  let tokens = formula_tokens(formula, spans~)
  let output = StringBuilder()
  let mut copied = 0
  for index in 0..<(tokens.length() - 1) {
    if tokens[index] is Word(name) &&
      [
        "IFNA", "CONCAT", "TEXTJOIN", "DAYS", "XLOOKUP", "VAR.S", "VAR.P", "STDEV.S",
        "STDEV.P", "MODE.SNGL", "MINIFS", "MAXIFS", "CEILING.MATH", "FLOOR.MATH",
        "CEILING.PRECISE", "FLOOR.PRECISE", "ISOWEEKNUM", "COMBINA",
      ].contains(name.to_upper()) &&
      tokens[index + 1] is Operator("(") {
      let (start, end) = spans[index]
      output.write_view(formula[copied:start])
      output.write_string("_xlfn.")
      output.write_view(formula[start:end])
      copied = end
    }
  }
  output.write_view(formula[copied:])
  output.to_string()
}

///|
fn FormulaAddress::shift(
  self : FormulaAddress,
  rows : Int,
  columns : Int,
) -> FormulaAddress raise @failure.Failure {
  let address = {
    row: self.address.row + (if self.fixed_row { 0 } else { rows }),
    column: self.address.column + (if self.fixed_column { 0 } else { columns }),
  }
  ignore(address.name())
  { ..self, address, }
}

///|
fn FormulaAddress::source(
  self : FormulaAddress,
) -> String raise @failure.Failure {
  let name = self.address.name()
  let letters = name[:name.length() - self.address.row.to_string().length()].to_owned()
  (if self.fixed_column { "$" } else { "" }) +
  letters +
  (if self.fixed_row { "$" } else { "" }) +
  self.address.row.to_string()
}

///|
fn Expression::source(
  self : Expression,
  rows~ : Int = 0,
  columns~ : Int = 0,
  depth~ : Int = 0,
  invalid_ref~ : Bool = false,
) -> String raise @failure.Failure {
  guard depth <= 64 else {
    @failure.reject("limit-exceeded", "Formula expression depth exceeded")
  }
  match self {
    Structured(name, selector) => name.unwrap_or("") + selector
    Named(sheet, name) =>
      sheet
      .map(sheet => "'" + sheet.replace_all(old="'", new="''") + "'!")
      .unwrap_or("") +
      name
    Constant(Text(value)) =>
      "\"" + value.replace_all(old="\"", new="\"\"") + "\""
    Constant(value) => value.display()
    Reference(sheet, first, last) =>
      try {
        let prefix = sheet
          .map(name => "'" + name.replace_all(old="'", new="''") + "'!")
          .unwrap_or("")
        let a = first.shift(rows, columns)
        if last is Some(last) {
          let b = last.shift(rows, columns)
          let range = a.range(b)
          if a.fixed_row &&
            b.fixed_row &&
            range.top == 1 &&
            range.bottom == 1048576 {
            return prefix +
              (if a.fixed_column { "$" } else { "" }) +
              print_column(a.address.column) +
              ":" +
              (if b.fixed_column { "$" } else { "" }) +
              print_column(b.address.column)
          }
          if a.fixed_column &&
            b.fixed_column &&
            range.left == 1 &&
            range.right == 16384 {
            return prefix +
              (if a.fixed_row { "$" } else { "" }) +
              a.address.row.to_string() +
              ":" +
              (if b.fixed_row { "$" } else { "" }) +
              b.address.row.to_string()
          }
        }
        prefix +
        a.source() +
        last.map(last => ":" + last.shift(rows, columns).source()).unwrap_or("")
      } catch {
        @failure.Failure(code~, ..) if invalid_ref && code == "invalid-address" =>
          "#REF!"
        error => raise error
      }
    Unary("%", value) =>
      "(" + value.source(rows~, columns~, depth=depth + 1, invalid_ref~) + ")%"
    Unary(operator, value) =>
      operator +
      "(" +
      value.source(rows~, columns~, depth=depth + 1, invalid_ref~) +
      ")"
    Binary(operator, left, right) =>
      "(" +
      left.source(rows~, columns~, depth=depth + 1, invalid_ref~) +
      operator +
      right.source(rows~, columns~, depth=depth + 1, invalid_ref~) +
      ")"
    Function(name, args) =>
      (if [
          "IFNA", "CONCAT", "TEXTJOIN", "DAYS", "XLOOKUP", "VAR.S", "VAR.P", "STDEV.S",
          "STDEV.P", "MODE.SNGL", "MINIFS", "MAXIFS", "CEILING.MATH", "FLOOR.MATH",
          "CEILING.PRECISE", "FLOOR.PRECISE", "ISOWEEKNUM", "COMBINA",
        ].contains(name) {
        "_xlfn." + name
      } else {
        name
      }) +
      "(" +
      args
      .map(arg => arg.source(rows~, columns~, depth=depth + 1, invalid_ref~))
      .join(",") +
      ")"
  }
}
