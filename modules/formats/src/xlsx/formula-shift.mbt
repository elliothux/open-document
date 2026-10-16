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
    Constant(Text(value)) =>
      "\"" + value.replace_all(old="\"", new="\"\"") + "\""
    Constant(value) => value.display()
    Reference(sheet, first, last) =>
      try {
        let prefix = sheet
          .map(name => "'" + name.replace_all(old="'", new="''") + "'!")
          .unwrap_or("")
        prefix +
        first.shift(rows, columns).source() +
        last.map(last => ":" + last.shift(rows, columns).source()).unwrap_or("")
      } catch {
        @failure.Failure(code~, ..) if invalid_ref && code == "invalid-address" =>
          "#REF!"
        error => raise error
      }
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
      name +
      "(" +
      args
      .map(arg => arg.source(rows~, columns~, depth=depth + 1, invalid_ref~))
      .join(",") +
      ")"
  }
}
