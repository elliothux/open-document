///|
fn numeric_value(value : Value) -> Value {
  match value {
    Blank => Number(0)
    Boolean(value) => Number(if value { 1 } else { 0 })
    Number(_) | Error(_) => value
    Text(text) => {
      let number = @string.parse_double(text.trim()) catch {
        _ => return Error("#VALUE!")
      }
      if number.is_nan() || number.is_inf() {
        Error("#VALUE!")
      } else {
        Number(number)
      }
    }
  }
}

///|
fn finite_result(value : Double) -> Value {
  if value.is_nan() || value.is_inf() {
    Error("#NUM!")
  } else {
    Number(value)
  }
}

///|
fn comparable(left : Value, right : Value) -> Int {
  match (left, right) {
    (Blank, Blank) => 0
    (Blank, Text(text)) => "".compare(text.to_lower())
    (Text(text), Blank) => text.to_lower().compare("")
    (Blank, Number(number)) => 0.0.compare(number)
    (Number(number), Blank) => number.compare(0.0)
    (Blank, Boolean(value)) => false.compare(value)
    (Boolean(value), Blank) => value.compare(false)
    (Number(a), Number(b)) => a.compare(b)
    (Text(a), Text(b)) => a.to_lower().compare(b.to_lower())
    (Boolean(a), Boolean(b)) => a.compare(b)
    (Number(_), _) => -1
    (_, Number(_)) => 1
    (Text(_), _) => -1
    (_, Text(_)) => 1
    _ => 0
  }
}

///|
fn calculated_cell(
  sheets : Array[Sheet],
  values : Map[(Int, String), Value],
  sheet : Int,
  address : Address,
) -> Value raise @failure.Failure {
  let name = address.name()
  if values.get((sheet, name)) is Some(value) {
    return value
  }
  match sheets[sheet].cells.get(name) {
    Some(cell) => {
      guard cell.calculation_supported else {
        @failure.reject(
          "unsupported-formula",
          "Formula references an unsupported cell value: " + name,
        )
      }
      cell.value
    }
    None => Blank
  }
}

///|
fn Expression::evaluate(
  self : Expression,
  sheets : Array[Sheet],
  sheet : Int,
  values : Map[(Int, String), Value],
  work : FormulaWork,
  depth : Int,
) -> Value raise @failure.Failure {
  work.spend()
  guard depth <= 64 else {
    @failure.reject("limit-exceeded", "Formula evaluation depth exceeded")
  }
  match self {
    Constant(value) => value
    Reference(name, first, last) => {
      if last is Some(last) && last.address != first.address {
        return Error("#VALUE!")
      }
      calculated_cell(
        sheets,
        values,
        referenced_sheet(sheets, sheet, name),
        first.address,
      )
    }
    Unary(operator, expression) =>
      match
        numeric_value(
          expression.evaluate(sheets, sheet, values, work, depth + 1),
        ) {
        Number(value) =>
          finite_result(if operator == "-" { -value } else { value })
        value => value
      }
    Binary(operator, a, b) => {
      let left = a.evaluate(sheets, sheet, values, work, depth + 1)
      if left is Error(_) {
        return left
      }
      let right = b.evaluate(sheets, sheet, values, work, depth + 1)
      if right is Error(_) {
        return right
      }
      if ["=", "<>", "<", ">", "<=", ">="].contains(operator) {
        let comparison = comparable(left, right)
        return Boolean(
          match operator {
            "=" => comparison == 0
            "<>" => comparison != 0
            "<" => comparison < 0
            ">" => comparison > 0
            "<=" => comparison <= 0
            _ => comparison >= 0
          },
        )
      }
      match (numeric_value(left), numeric_value(right)) {
        (Error(error), _) | (_, Error(error)) => Error(error)
        (Number(left), Number(right)) =>
          match operator {
            "+" => finite_result(left + right)
            "-" => finite_result(left - right)
            "*" => finite_result(left * right)
            "/" =>
              if right == 0 {
                Error("#DIV/0!")
              } else {
                finite_result(left / right)
              }
            _ => Error("#VALUE!")
          }
        _ => Error("#VALUE!")
      }
    }
    Function("IF", args) => {
      let condition = args[0].evaluate(sheets, sheet, values, work, depth + 1)
      let condition = match condition {
        Text(text) if text.to_upper() == "TRUE" => Boolean(true)
        Text(text) if text.to_upper() == "FALSE" => Boolean(false)
        value => value
      }
      if condition is Text(_) {
        return Error("#VALUE!")
      }
      match numeric_value(condition) {
        Error(error) => Error(error)
        Number(condition) => {
          let index = if condition != 0 { 1 } else { 2 }
          guard args.get(index) is Some(expression) else {
            return Boolean(false)
          }
          match expression.evaluate(sheets, sheet, values, work, depth + 1) {
            Blank => Number(0)
            value => value
          }
        }
        _ => Error("#VALUE!")
      }
    }
    Function(name, args) => {
      let numbers : Array[Double] = []
      for arg in args {
        if arg is Reference(target, first, last) {
          let target = referenced_sheet(sheets, sheet, target)
          let last = last.unwrap_or(first)
          let range = first.range(last)
          for key, cell in sheets[target].cells {
            work.spend()
            if !range.contains(cell.address) {
              continue
            }
            guard cell.calculation_supported else {
              @failure.reject(
                "unsupported-formula",
                "Formula range contains an unsupported cell value: " + key,
              )
            }
            let value = values.get((target, key)).unwrap_or(cell.value)
            match value {
              Number(value) => numbers.push(value)
              Error(error) if name != "COUNT" => return Error(error)
              _ => ()
            }
          }
        } else {
          let value = arg.evaluate(sheets, sheet, values, work, depth + 1)
          match numeric_value(value) {
            Number(number) => numbers.push(number)
            Error(error) if name != "COUNT" => return Error(error)
            _ => ()
          }
        }
      }
      match name {
        "COUNT" => Number(numbers.length().to_double())
        "SUM" | "AVERAGE" => {
          if name == "AVERAGE" && numbers.is_empty() {
            return Error("#DIV/0!")
          }
          let total = numbers
            .iter()
            .fold(init=0.0, (total, value) => total + value)
          finite_result(
            if name == "AVERAGE" {
              total / numbers.length().to_double()
            } else {
              total
            },
          )
        }
        "MIN" | "MAX" => {
          let value = numbers.get(0).unwrap_or(0)
          finite_result(
            numbers
            .iter()
            .fold(init=value, (result, value) => {
              if name == "MIN" {
                result.min(value)
              } else {
                result.max(value)
              }
            }),
          )
        }
        _ =>
          @failure.reject(
            "unsupported-formula", "Unsupported aggregate function",
          )
      }
    }
  }
}
