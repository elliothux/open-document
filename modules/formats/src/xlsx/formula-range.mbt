///|
priv struct FormulaRange {
  sheet : Int
  bounds : Range
}

///|
fn Expression::scalar_argument(
  self : Expression,
  sheets : Array[Sheet],
  sheet : Int,
  values : Map[(Int, String), Value],
  work : FormulaWork,
  depth : Int,
) -> Value raise @failure.Failure {
  guard self.aggregate_range(sheets, sheet) is Some(range) else {
    return self.evaluate(sheets, sheet, values, work, depth)
  }
  work.spend()
  let bounds = range.bounds
  let address = if bounds.top == bounds.bottom && bounds.left == bounds.right {
    Address::{ row: bounds.top, column: bounds.left, }
  } else if bounds.left == bounds.right &&
    work.origin.row >= bounds.top &&
    work.origin.row <= bounds.bottom {
    Address::{ row: work.origin.row, column: bounds.left, }
  } else if bounds.top == bounds.bottom &&
    work.origin.column >= bounds.left &&
    work.origin.column <= bounds.right {
    Address::{ row: bounds.top, column: work.origin.column, }
  } else {
    return Error("#VALUE!")
  }
  calculated_cell(sheets, values, range.sheet, address)
}

///|
fn Expression::aggregate_range(
  self : Expression,
  sheets : Array[Sheet],
  sheet : Int,
) -> FormulaRange? raise @failure.Failure {
  guard self is Reference(target, first, last) else { return None }
  Some({
    sheet: referenced_sheet(sheets, sheet, target),
    bounds: first.range(last.unwrap_or(first)),
  })
}

///|
fn FormulaRange::fit(self : FormulaRange, shape : Range) -> FormulaRange? {
  let bottom = self.bounds.top + shape.bottom - shape.top
  let right = self.bounds.left + shape.right - shape.left
  guard bottom <= 1048576 && right <= 16384 else { return None }
  Some({ sheet: self.sheet, bounds: { ..self.bounds, bottom, right, }, })
}

///|
fn FormulaRange::area(self : FormulaRange) -> Int64 {
  (self.bounds.bottom - self.bounds.top + 1).to_int64() *
  (self.bounds.right - self.bounds.left + 1).to_int64()
}

///|
fn FormulaRange::offset(self : FormulaRange, address : Address) -> Int64 {
  (address.row - self.bounds.top).to_int64() *
  (self.bounds.right - self.bounds.left + 1).to_int64() +
  (address.column - self.bounds.left).to_int64()
}

///|
fn FormulaRange::value(
  self : FormulaRange,
  offset : Int64,
  sheets : Array[Sheet],
  calculated : Map[(Int, String), Value],
  work : FormulaWork,
) -> Value raise @failure.Failure {
  work.spend()
  let width = (self.bounds.right - self.bounds.left + 1).to_int64()
  calculated_cell(sheets, calculated, self.sheet, {
    row: self.bounds.top + (offset / width).to_int(),
    column: self.bounds.left + (offset % width).to_int(),
  })
}

///|
fn aggregate_offsets(
  ranges : Array[FormulaRange],
  sheets : Array[Sheet],
  work : FormulaWork,
) -> Array[Int64] raise @failure.Failure {
  let offsets : Map[Int64, Bool] = Map([])
  for range in ranges {
    for _, cell in sheets[range.sheet].cells {
      work.spend()
      if range.bounds.contains(cell.address) {
        offsets[range.offset(cell.address)] = true
      }
    }
  }
  let result = offsets.keys().to_array()
  work.spend(amount=result.length())
  result.sort()
  result
}
