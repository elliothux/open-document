///|
fn logical_value(value : Value) -> Value {
  match value {
    Blank => Boolean(false)
    Boolean(_) | Error(_) => value
    Number(value) => Boolean(value != 0)
    Text(text) =>
      match text.to_upper() {
        "TRUE" => Boolean(true)
        "FALSE" => Boolean(false)
        _ => Error("#VALUE!")
      }
  }
}

///|
fn formula_result(value : Value) -> Value {
  match value {
    Blank => Number(0)
    value => value
  }
}

///|
fn logical_function(
  name : String,
  args : Array[Expression],
  sheets : Array[Sheet],
  sheet : Int32,
  values : Map[(Int32, String), Value],
  work : FormulaWork,
  depth : Int32,
  hyperlink~ : Ref[String?]? = None,
) -> Value raise @failure.Failure {
  if name == "AND" || name == "OR" {
    let mut result = name == "AND"
    let mut seen = false
    for arg in args {
      if arg is Reference(target, first, last) {
        let target = referenced_sheet(sheets, sheet, target)
        let range = first.range(last.unwrap_or(first))
        let mut error : (Address, String)? = None
        // Sparse references skip text/blanks, but every error still participates.
        for _, cell in sheets[target].cells {
          work.spend()
          if !range.contains(cell.address) {
            continue
          }
          match calculated_cell(sheets, values, target, cell.address) {
            Text(_) | Blank => ()
            Error(message) =>
              if error is None ||
                (
                  error is Some((address, _)) &&
                  (
                    cell.address.row < address.row ||
                    (
                      cell.address.row == address.row &&
                      cell.address.column < address.column
                    )
                  )
                ) {
                error = Some((cell.address, message))
              }
            value => {
              let logical = logical_value(value) == Boolean(true)
              result = if name == "AND" {
                result && logical
              } else {
                result || logical
              }
              seen = true
            }
          }
        }
        if error is Some((_, message)) {
          return Error(message)
        }
      } else {
        let value = arg.evaluate(sheets, sheet, values, work, depth + 1)
        // Logical aggregates do not coerce literal text to numbers or booleans.
        if value is Text(_) {
          return Error("#VALUE!")
        }
        if value is Error(_) {
          return value
        }
        let logical = logical_value(value) == Boolean(true)
        result = if name == "AND" {
          result && logical
        } else {
          result || logical
        }
        seen = true
      }
    }
    return if seen { Boolean(result) } else { Error("#VALUE!") }
  }
  if ["ISBLANK", "ISNUMBER", "ISTEXT"].contains(name) &&
    args[0] is Reference(_, first, Some(last)) &&
    first.address != last.address {
    return Error("#VALUE!")
  }
  let value = args[0].evaluate(
    sheets,
    sheet,
    values,
    work,
    depth + 1,
    hyperlink=if name == "IFERROR" || name == "IFNA" { hyperlink } else { None },
  )
  match name {
    "IFERROR" | "IFNA" => {
      let fallback = value is Error(message) &&
        (name == "IFERROR" || message == "#N/A")
      formula_result(
        if fallback {
          args[1].evaluate(sheets, sheet, values, work, depth + 1, hyperlink~)
        } else {
          value
        },
      )
    }
    "ISBLANK" => Boolean(value is Blank)
    "ISNUMBER" => Boolean(value is Number(_))
    "ISTEXT" => Boolean(value is Text(_))
    "NOT" =>
      match logical_value(value) {
        Boolean(value) => Boolean(!value)
        value => value
      }
    _ => abort("Unexpected logical function")
  }
}
