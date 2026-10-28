///|
fn position_function(
  name : String,
  args : Array[Expression],
  sheets : Array[Sheet],
  sheet : Int32,
  work : FormulaWork,
) -> Value raise @failure.Failure {
  let range = if args.is_empty() {
    {
      top: work.origin.row,
      bottom: work.origin.row,
      left: work.origin.column,
      right: work.origin.column,
    }
  } else {
    guard args[0].aggregate_range(sheets, sheet) is Some(range) else {
      return Error(
        if name == "ROW" || name == "COLUMN" {
          "#REF!"
        } else {
          "#VALUE!"
        },
      )
    }
    range.bounds
  }
  Number(
    (match name {
      "ROW" => range.top
      "COLUMN" => range.left
      "ROWS" => range.bottom - range.top + 1
      _ => range.right - range.left + 1
    }).to_double(),
  )
}

///|
fn lookup_function(
  name : String,
  args : Array[Expression],
  sheets : Array[Sheet],
  sheet : Int32,
  calculated : Map[(Int32, String), Value],
  work : FormulaWork,
  depth : Int32,
  hyperlink~ : Ref[String?]? = None,
) -> Value raise @failure.Failure {
  let argument = (index : Int32, default : Value) => {
    match args.get(index) {
      Some(arg) => arg.evaluate(sheets, sheet, calculated, work, depth + 1)
      None => default
    }
  }
  if name == "INDEX" {
    let range = args[0].aggregate_range(sheets, sheet)
    let scalar_link : Ref[String?] = Ref(None)
    let scalar = if range is None {
      args[0].evaluate(
        sheets,
        sheet,
        calculated,
        work,
        depth + 1,
        hyperlink=Some(scalar_link),
      )
    } else {
      Blank
    }
    if scalar is Error(_) {
      return scalar
    }
    let parameters : Array[Double] = []
    for index in 1..<args.length() {
      let value = argument(index, Number(0))
      let value = numeric_value(
        if index == 3 && value == Blank {
          Number(1)
        } else {
          value
        },
      )
      guard value is Number(value) else { return value }
      if index < 3 && value < 0 {
        return Error("#VALUE!")
      }
      parameters.push(if index == 3 { value } else { value.trunc() })
    }
    if parameters.get(2).unwrap_or(1) != 1 {
      return Error("#REF!")
    }
    let height = range
      .map(range => range.bounds.bottom - range.bounds.top + 1)
      .unwrap_or(1)
    let width = range
      .map(range => range.bounds.right - range.bounds.left + 1)
      .unwrap_or(1)
    let row = parameters[0]
    let column = parameters.get(1).unwrap_or(if height == 1 { row } else { 1 })
    let row = if args.length() == 2 && height == 1 { 1.0 } else { row }
    if row < 0 || column < 0 {
      return Error("#VALUE!")
    }
    if row > height.to_double() || column > width.to_double() {
      return Error("#REF!")
    }
    // shortcut: INDEX returns one cell; row/column arrays need the P14 array value model.
    let row = if row == 0 && height == 1 { 1.0 } else { row }
    let column = if column == 0 && width == 1 { 1.0 } else { column }
    if row == 0 || column == 0 {
      return Error("#VALUE!")
    }
    if range is None && hyperlink is Some(hyperlink) {
      hyperlink.val = scalar_link.val
    }
    return formula_result(
      if range is Some(range) {
        range.value(
          (row.to_int64() - 1) * width.to_int64() + column.to_int64() - 1,
          sheets,
          calculated,
          work,
        )
      } else {
        scalar
      },
    )
  }
  let needle = argument(0, Blank)
  if needle is Error(_) {
    return needle
  }
  let needle = formula_result(needle)
  guard args[1].aggregate_range(sheets, sheet) is Some(table) else {
    let value = argument(1, Blank)
    return if value is Error(_) { value } else { Error("#N/A") }
  }
  let height = table.bounds.bottom - table.bounds.top + 1
  let width = table.bounds.right - table.bounds.left + 1
  let mut range = table
  let mut target = table
  let mut result_index = 0
  let mut mode = 0
  let mut search = 1
  let mut last_equal = false
  if name == "MATCH" {
    if height != 1 && width != 1 {
      return Error("#N/A")
    }
    let value = numeric_value(argument(2, Number(1)))
    guard value is Number(value) else { return value }
    let value = value.floor()
    if value != -1 && value != 0 && value != 1 {
      return Error("#VALUE!")
    }
    mode = if value == 0 { 2 } else if value > 0 { -1 } else { 1 }
    search = if value == 0 { 1 } else if value > 0 { 2 } else { -2 }
    last_equal = value != 0
  } else if name == "XLOOKUP" {
    guard args[2].aggregate_range(sheets, sheet) is Some(result) else {
      let value = argument(2, Blank)
      return if value is Error(_) { value } else { Error("#N/A") }
    }
    if (height != 1 && width != 1) ||
      result.bounds.bottom - result.bounds.top + 1 != height ||
      result.bounds.right - result.bounds.left + 1 != width {
      return Error("#VALUE!")
    }
    target = result
    let match_mode = numeric_value(argument(4, Number(0)))
    guard match_mode is Number(match_mode) else { return match_mode }
    let search_mode = numeric_value(argument(5, Number(1)))
    guard search_mode is Number(search_mode) else { return search_mode }
    if ![-1.0, 0, 1, 2].contains(match_mode.trunc()) ||
      ![-2.0, -1, 1, 2].contains(search_mode.trunc()) {
      return Error("#VALUE!")
    }
    mode = match_mode.trunc().to_int()
    search = search_mode.trunc().to_int()
    if mode == 2 && search.abs() == 2 {
      return Error("#VALUE!")
    }
  } else {
    let value = numeric_value(argument(2, Number(0)))
    guard value is Number(value) else { return value }
    if value < 1 {
      return Error("#VALUE!")
    }
    let maximum = if name == "VLOOKUP" { width } else { height }
    if value.trunc() > maximum.to_double() {
      return Error("#REF!")
    }
    result_index = value.trunc().to_int() - 1
    let approximate = logical_value(argument(3, Boolean(true)))
    guard approximate is Boolean(approximate) else { return approximate }
    mode = if approximate { -1 } else { 2 }
    search = if approximate { 2 } else { 1 }
    last_equal = approximate
    range = {
      sheet: table.sheet,
      bounds: if name == "VLOOKUP" {
        { ..table.bounds, right: table.bounds.left, }
      } else {
        { ..table.bounds, bottom: table.bounds.top, }
      },
    }
  }
  match
    lookup_search(
      range,
      needle,
      mode,
      search,
      last_equal,
      name == "XLOOKUP",
      sheets,
      calculated,
      work,
    ) {
    Failed(error) => Error(error)
    Missing =>
      if name == "XLOOKUP" && !(args.get(3) is Some(Constant(Blank))) {
        formula_result(
          match args.get(3) {
            Some(arg) =>
              arg.evaluate(
                sheets,
                sheet,
                calculated,
                work,
                depth + 1,
                hyperlink~,
              )
            None => Error("#N/A")
          },
        )
      } else {
        Error("#N/A")
      }
    Found(index) => {
      if name == "MATCH" {
        return Number((index + 1).to_double())
      }
      let offset = match name {
        "VLOOKUP" =>
          index.to_int64() * width.to_int64() + result_index.to_int64()
        "HLOOKUP" =>
          result_index.to_int64() * width.to_int64() + index.to_int64()
        _ => index.to_int64()
      }
      formula_result(target.value(offset, sheets, calculated, work))
    }
  }
}
