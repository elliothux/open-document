///|
priv struct ProductArray {
  rows : Int
  columns : Int
  expression : Expression
  ranges : Array[FormulaRange]
}

///|
fn Expression::product_array(
  self : Expression,
  sheets : Array[Sheet],
  sheet : Int,
  values : Map[(Int, String), Value],
  work : FormulaWork,
  depth : Int,
) -> ProductArray raise @failure.Failure {
  work.spend()
  guard depth <= 64 else {
    @failure.reject("limit-exceeded", "Formula evaluation depth exceeded")
  }
  let scalar = fn(value) {
    { rows: 0, columns: 0, expression: Constant(value), ranges: [], }
  }
  match self {
    Reference(_, _, Some(_)) => {
      let range = self.aggregate_range(sheets, sheet).unwrap()
      {
        rows: range.bounds.bottom - range.bounds.top + 1,
        columns: range.bounds.right - range.bounds.left + 1,
        expression: self,
        ranges: [range],
      }
    }
    Unary(operator, expression) => {
      let array = expression.product_array(
        sheets,
        sheet,
        values,
        work,
        depth + 1,
      )
      { ..array, expression: Unary(operator, array.expression), }
    }
    Binary(operator, left, right) => {
      let left = left.product_array(sheets, sheet, values, work, depth + 1)
      let right = right.product_array(sheets, sheet, values, work, depth + 1)
      if left.rows > 0 &&
        right.rows > 0 &&
        (left.rows != right.rows || left.columns != right.columns) {
        return scalar(Error("#VALUE!"))
      }
      {
        rows: left.rows.max(right.rows),
        columns: left.columns.max(right.columns),
        expression: Binary(operator, left.expression, right.expression),
        ranges: left.ranges + right.ranges,
      }
    }
    _ => scalar(self.evaluate(sheets, sheet, values, work, depth + 1))
  }
}

///|
fn Expression::product_element(
  self : Expression,
  row : Int,
  column : Int,
  blank : Bool,
  sheets : Array[Sheet],
  sheet : Int,
  values : Map[(Int, String), Value],
  work : FormulaWork,
  depth : Int,
) -> Expression raise @failure.Failure {
  work.spend()
  guard depth <= 64 else {
    @failure.reject("limit-exceeded", "Formula evaluation depth exceeded")
  }
  match self {
    Reference(_, _, Some(_)) => {
      let range = self.aggregate_range(sheets, sheet).unwrap()
      Constant(
        if blank {
          Blank
        } else {
          range.value(
            row.to_int64() *
            (range.bounds.right - range.bounds.left + 1).to_int64() +
            column.to_int64(),
            sheets,
            values,
            work,
          )
        },
      )
    }
    Unary(operator, expression) =>
      Unary(
        operator,
        expression.product_element(
          row,
          column,
          blank,
          sheets,
          sheet,
          values,
          work,
          depth + 1,
        ),
      )
    Binary(operator, left, right) =>
      Binary(
        operator,
        left.product_element(
          row,
          column,
          blank,
          sheets,
          sheet,
          values,
          work,
          depth + 1,
        ),
        right.product_element(
          row,
          column,
          blank,
          sheets,
          sheet,
          values,
          work,
          depth + 1,
        ),
      )
    _ => self
  }
}

///|
fn product_at(
  arrays : Array[ProductArray],
  row : Int,
  column : Int,
  blank : Bool,
  sheets : Array[Sheet],
  sheet : Int,
  values : Map[(Int, String), Value],
  work : FormulaWork,
  depth : Int,
) -> Value raise @failure.Failure {
  let mut product = 1.0
  for array in arrays {
    let value = if row >= array.rows.max(1) || column >= array.columns.max(1) {
      Blank
    } else {
      array.expression
      .product_element(
        row,
        column,
        blank,
        sheets,
        sheet,
        values,
        work,
        depth + 1,
      )
      .evaluate(sheets, sheet, values, work, depth + 1)
    }
    match value {
      Error(_) => return value
      Number(number) => product *= number
      Text(text) => {
        work.spend(amount=text.length())
        product *= match numeric_value(value) {
          Number(number) => number
          _ => 0.0
        }
      }
      Blank | Boolean(_) => product = 0
    }
  }
  Number(product)
}

///|
fn sum_product_function(
  args : Array[Expression],
  sheets : Array[Sheet],
  sheet : Int,
  values : Map[(Int, String), Value],
  work : FormulaWork,
  depth : Int,
) -> Value raise @failure.Failure {
  let arrays : Array[ProductArray] = []
  let mut rows = 0
  let mut columns = 0
  for arg in args {
    let array = arg.product_array(sheets, sheet, values, work, depth + 1)
    if arg is Reference(_, _, None) && array.expression is Constant(Blank) {
      return Error("#VALUE!")
    }
    rows = rows.max(array.rows.max(1))
    columns = columns.max(array.columns.max(1))
    // ONLYOFFICE validates each next matrix against the growing maximum dimensions.
    if rows != array.rows.max(1) || columns != array.columns.max(1) {
      return Error("#NUM!")
    }
    if array.expression is Constant(Error(_) as error) {
      return error
    }
    arrays.push(array)
  }
  let offsets : Map[Int64, Bool] = Map([])
  let row_edges : Map[Int, Bool] = Map([(0, true), (rows, true)])
  let column_edges : Map[Int, Bool] = Map([(0, true), (columns, true)])
  for array in arrays {
    row_edges[array.rows.max(1)] = true
    column_edges[array.columns.max(1)] = true
    for range in array.ranges {
      for _, cell in sheets[range.sheet].cells {
        work.spend()
        if range.bounds.contains(cell.address) {
          offsets[(cell.address.row - range.bounds.top).to_int64() *
          columns.to_int64() +
          (cell.address.column - range.bounds.left).to_int64()] = true
        }
      }
    }
  }
  let row_edges = row_edges.keys().to_array()
  let column_edges = column_edges.keys().to_array()
  row_edges.sort()
  column_edges.sort()
  let populated = offsets.keys().to_array()
  work.spend(amount=populated.length())
  populated.sort()
  let mut total = 0.0
  let mut first_error : (Int64, Value)? = None
  for offset in populated {
    let value = product_at(
      arrays,
      (offset / columns.to_int64()).to_int(),
      (offset % columns.to_int64()).to_int(),
      false,
      sheets,
      sheet,
      values,
      work,
      depth,
    )
    match value {
      Number(number) => total += number
      Error(_) =>
        if first_error is None || offset < first_error.unwrap().0 {
          first_error = Some((offset, value))
        }
      _ => abort("Expected numeric product")
    }
  }
  // Empty coordinates share one value within each matrix boundary rectangle.
  for r in 0..<(row_edges.length() - 1) {
    for c in 0..<(column_edges.length() - 1) {
      let top = row_edges[r]
      let bottom = row_edges[r + 1]
      let left = column_edges[c]
      let right = column_edges[c + 1]
      let mut missing = (bottom - top).to_int64() * (right - left).to_int64()
      for offset in populated {
        work.spend()
        let row = (offset / columns.to_int64()).to_int()
        let column = (offset % columns.to_int64()).to_int()
        if row >= top && row < bottom && column >= left && column < right {
          missing -= 1
        }
      }
      if missing == 0 {
        continue
      }
      let width = (right - left).to_int64()
      let mut cursor = 0L
      let mut first = top.to_int64() * columns.to_int64() + left.to_int64()
      while offsets.contains(first) {
        work.spend()
        cursor += 1
        first = (top.to_int64() + cursor / width) * columns.to_int64() +
          left.to_int64() +
          cursor % width
      }
      match
        product_at(arrays, top, left, true, sheets, sheet, values, work, depth) {
        Number(number) => total += number * missing.to_double()
        Error(_) as error =>
          if first_error is None || first < first_error.unwrap().0 {
            first_error = Some((first, error))
          }
        _ => abort("Expected numeric product")
      }
    }
  }
  match first_error {
    Some((_, error)) => error
    None => finite_result(total)
  }
}
