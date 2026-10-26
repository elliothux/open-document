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
      guard cell.formula is None else {
        @failure.reject("unsupported-formula", "Uncalculated formula: " + name)
      }
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
  hyperlink~ : Ref[String?]? = None,
) -> Value raise @failure.Failure {
  if hyperlink is Some(hyperlink) {
    hyperlink.val = None
  }
  work.spend()
  guard depth <= 64 else {
    @failure.reject("limit-exceeded", "Formula evaluation depth exceeded")
  }
  match self {
    Named(_, _) | Structured(_, _) =>
      self
      .resolve_names(sheets, sheet, work.origin, work)
      .evaluate(sheets, sheet, values, work, depth + 1, hyperlink~)
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
    Unary("%", expression) =>
      match
        numeric_value(
          expression.scalar_argument(sheets, sheet, values, work, depth + 1),
        ) {
        Number(value) => finite_result(value / 100)
        value => value
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
    Binary("^", a, b) =>
      numeric_function("POWER", [a, b], sheets, sheet, values, work, depth)
    Binary("&", a, b) => {
      let left = a.scalar_argument(sheets, sheet, values, work, depth + 1)
      if left is Error(_) {
        return left
      }
      let right = b.scalar_argument(sheets, sheet, values, work, depth + 1)
      if right is Error(_) {
        return right
      }
      let text = FormulaText::new()
      if !text.append(left.display(), work) ||
        !text.append(right.display(), work) {
        return Error("#VALUE!")
      }
      Text(text.output.to_string())
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
    Function("IF", args) =>
      match
        logical_value(args[0].evaluate(sheets, sheet, values, work, depth + 1)) {
        Error(error) => Error(error)
        Boolean(condition) => {
          let index = if condition { 1 } else { 2 }
          guard args.get(index) is Some(expression) else {
            return Boolean(false)
          }
          formula_result(
            expression.evaluate(
              sheets,
              sheet,
              values,
              work,
              depth + 1,
              hyperlink~,
            ),
          )
        }
        _ => Error("#VALUE!")
      }
    Function("HYPERLINK", args) => {
      let target = args[0].scalar_argument(
        sheets,
        sheet,
        values,
        work,
        depth + 1,
      )
      let friendly = args
        .get(1)
        .map(arg => arg.scalar_argument(sheets, sheet, values, work, depth + 1))
      if target is Error(_) {
        return target
      }
      if friendly is Some(Error(_) as error) {
        return error
      }
      let target = target.display()
      work.spend(amount=target.length())
      if hyperlink is Some(hyperlink) && !target.is_empty() {
        hyperlink.val = Some(target)
      }
      friendly.map(formula_result).unwrap_or(Text(target))
    }
    Function(name, args) if [
        "AND", "OR", "NOT", "IFERROR", "IFNA", "ISBLANK", "ISNUMBER", "ISTEXT",
      ].contains(name) =>
      logical_function(
        name,
        args,
        sheets,
        sheet,
        values,
        work,
        depth,
        hyperlink~,
      )
    Function(name, args) if [
        "DATE", "YEAR", "MONTH", "DAY", "TIME", "HOUR", "MINUTE", "SECOND", "DAYS",
        "WEEKDAY", "WEEKNUM", "ISOWEEKNUM",
      ].contains(name) =>
      date_function(name, args, sheets, sheet, values, work, depth)
    Function(name, args) if [
        "ABS", "INT", "MOD", "ROUND", "ROUNDUP", "ROUNDDOWN", "SQRT", "POWER", "PI",
        "SIN", "COS", "TAN", "ACOS", "ASIN", "ATAN", "ATAN2", "EXP", "LN", "LOG",
        "LOG10", "RADIANS", "DEGREES", "SINH", "COSH", "TANH", "ACOSH", "ASINH",
        "ATANH", "SIGN", "CEILING.MATH", "FLOOR.MATH", "CEILING.PRECISE", "FLOOR.PRECISE",
        "CEILING", "FLOOR", "TRUNC", "FACT", "FACTDOUBLE", "COMBIN", "COMBINA", "MROUND",
        "QUOTIENT",
      ].contains(name) =>
      numeric_function(name, args, sheets, sheet, values, work, depth)
    Function(name, args) if [
        "LEN", "LEFT", "RIGHT", "MID", "TRIM", "UPPER", "LOWER", "CONCAT", "CONCATENATE",
        "TEXTJOIN", "FIND", "SEARCH", "SUBSTITUTE", "EXACT", "REPT", "TEXT",
      ].contains(name) =>
      text_function(name, args, sheets, sheet, values, work, depth)
    Function(name, args) if ["ROW", "COLUMN", "ROWS", "COLUMNS"].contains(name) =>
      position_function(name, args, sheets, sheet, work)
    Function(name, args) if ["INDEX", "MATCH", "VLOOKUP", "HLOOKUP", "XLOOKUP"].contains(
        name,
      ) =>
      lookup_function(
        name,
        args,
        sheets,
        sheet,
        values,
        work,
        depth,
        hyperlink~,
      )
    Function("SUBTOTAL", args) =>
      subtotal_function(args, sheets, sheet, values, work, depth)
    Function("SUMSQ", args) =>
      sum_squares_function(args, sheets, sheet, values, work, depth)
    Function("MULTINOMIAL", args) =>
      multinomial_function(args, sheets, sheet, values, work, depth)
    Function("SERIESSUM", args) =>
      series_sum_function(args, sheets, sheet, values, work, depth)
    Function("SUMX2MY2" | "SUMX2PY2" | "SUMXMY2" as name, args) =>
      paired_squares_function(name, args, sheets, sheet, values, work, depth)
    Function("MDETERM", args) =>
      determinant_function(args[0], sheets, sheet, values, work, depth)
    Function("SUMPRODUCT", args) =>
      sum_product_function(args, sheets, sheet, values, work, depth)
    Function("DEVSQ", args) =>
      deviation_squares_function(args, sheets, sheet, values, work, depth)
    Function(name, args) if [
        "VAR", "VAR.S", "VARP", "VAR.P", "STDEV", "STDEV.S", "STDEVP", "STDEV.P",
      ].contains(name) =>
      statistical_function(name, args, sheets, sheet, values, work, depth)
    Function(name, args) if name == "GCD" || name == "LCM" =>
      factor_function(name, args, sheets, sheet, values, work, depth)
    Function(name, args) if ["PRODUCT", "MEDIAN", "MODE", "MODE.SNGL"].contains(
        name,
      ) =>
      aggregate_numeric_function(name, args, sheets, sheet, values, work, depth)
    Function(name, args) if name == "LARGE" || name == "SMALL" =>
      order_statistic_function(name, args, sheets, sheet, values, work, depth)
    Function(name, args) if name == "COUNTA" || name == "COUNTBLANK" =>
      counting_function(name, args, sheets, sheet, values, work, depth)
    Function(name, args) if [
        "COUNTIF", "COUNTIFS", "SUMIF", "SUMIFS", "AVERAGEIF", "AVERAGEIFS", "MINIFS",
        "MAXIFS",
      ].contains(name) =>
      conditional_function(name, args, sheets, sheet, values, work, depth)
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
