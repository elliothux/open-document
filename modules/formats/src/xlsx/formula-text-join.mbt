///|
fn Expression::text_items(
  self : Expression,
  sheets : Array[Sheet],
  sheet : Int32,
  calculated : Map[(Int32, String), Value],
  work : FormulaWork,
  depth : Int32,
  include_blanks : Bool,
) -> Array[Value] raise @failure.Failure {
  guard self is Reference(target, first, Some(last)) else {
    return [self.evaluate(sheets, sheet, calculated, work, depth + 1)]
  }
  let target = referenced_sheet(sheets, sheet, target)
  let range = first.range(last)
  let values : Array[Value] = []
  if include_blanks {
    let area = (range.bottom - range.top + 1).to_int64() *
      (range.right - range.left + 1).to_int64()
    guard area <= work.remaining.to_int64() else {
      @failure.reject(
        "limit-exceeded", "Formula range iteration exceeds calculation budget",
      )
    }
    work.spend(amount=area.to_int())
    for row in range.top..<=range.bottom {
      for column in range.left..<=range.right {
        values.push(
          calculated_cell(sheets, calculated, target, { row, column, }),
        )
      }
    }
  } else {
    let cells : Array[Cell] = []
    for _, cell in sheets[target].cells {
      work.spend()
      if range.contains(cell.address) {
        cells.push(cell)
      }
    }
    cells.sort_by((a, b) => {
      let row = a.address.row.compare(b.address.row)
      if row == 0 {
        a.address.column.compare(b.address.column)
      } else {
        row
      }
    })
    for cell in cells {
      values.push(calculated_cell(sheets, calculated, target, cell.address))
    }
  }
  values
}

///|
fn join_function(
  name : String,
  args : Array[Expression],
  sheets : Array[Sheet],
  sheet : Int32,
  calculated : Map[(Int32, String), Value],
  work : FormulaWork,
  depth : Int32,
) -> Value raise @failure.Failure {
  let delimiters : Array[String] = []
  let ignore_empty = if name == "TEXTJOIN" {
    for
      value in args[0].text_items(sheets, sheet, calculated, work, depth, true) {
      if value is Error(_) {
        return value
      }
      let text = value.display()
      work.spend(amount=text.length())
      delimiters.push(text)
    }
    let ignore_empty = logical_value(
      args[1].evaluate(sheets, sheet, calculated, work, depth + 1),
    )
    guard ignore_empty is Boolean(ignore_empty) else { return ignore_empty }
    ignore_empty
  } else {
    delimiters.push("")
    false
  }
  let out = FormulaText::new()
  let mut count = 0
  for index in (if name == "TEXTJOIN" { 2 } else { 0 })..<args.length() {
    let items = if name == "CONCATENATE" {
      [args[index].evaluate(sheets, sheet, calculated, work, depth + 1)]
    } else {
      args[index].text_items(
        sheets,
        sheet,
        calculated,
        work,
        depth,
        name == "TEXTJOIN" && !ignore_empty,
      )
    }
    for value in items {
      if value is Error(_) {
        return value
      }
      let text = value.display()
      if ignore_empty && text.is_empty() {
        continue
      }
      if count > 0 &&
        !out.append(delimiters[(count - 1) % delimiters.length()], work) {
        return Error("#VALUE!")
      }
      if !out.append(text, work) {
        return Error("#VALUE!")
      }
      count += 1
    }
  }
  Text(out.output.to_string())
}
