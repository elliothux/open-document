///|
fn Expression::transpose(
  self : Expression,
  top : Int32,
  left : Int32,
  depth~ : Int32 = 0,
) -> Expression raise @failure.Failure {
  guard depth <= 64 else {
    @failure.reject("limit-exceeded", "Formula expression depth exceeded")
  }
  let next = fn(expression : Expression) raise @failure.Failure {
    expression.transpose(top, left, depth=depth + 1)
  }
  match self {
    Reference(sheet, first, last) => {
      if last is Some(last) {
        if first.fixed_row &&
          last.fixed_row &&
          first.address.row == 1 &&
          last.address.row == 1048576 {
          return Reference(
            sheet,
            {
              address: { row: top + first.address.column - left, column: 1, },
              fixed_row: first.fixed_column,
              fixed_column: true,
            },
            Some({
              address: { row: top + last.address.column - left, column: 16384, },
              fixed_row: last.fixed_column,
              fixed_column: true,
            }),
          )
        }
        if first.fixed_column &&
          last.fixed_column &&
          first.address.column == 1 &&
          last.address.column == 16384 {
          return Reference(
            sheet,
            {
              address: { row: 1, column: left + first.address.row - top, },
              fixed_row: true,
              fixed_column: first.fixed_row,
            },
            Some({
              address: { row: 1048576, column: left + last.address.row - top, },
              fixed_row: true,
              fixed_column: last.fixed_row,
            }),
          )
        }
      }
      let address = fn(value : FormulaAddress) {
        {
          ..value,
          address: {
            row: top + value.address.column - left,
            column: left + value.address.row - top,
          },
        }
      }
      let a = address(first)
      let b = last.map(address)
      Reference(sheet, a, b)
    }
    Unary(operator, value) => Unary(operator, next(value))
    Binary(operator, a, b) => Binary(operator, next(a), next(b))
    Function(name, args) => Function(name, args.map(next))
    expression => expression
  }
}

///|
fn CellFormat::transposed(self : CellFormat) -> CellFormat {
  {
    ..self,
    left: self.top,
    top: self.left,
    right: self.bottom,
    bottom: self.right,
  }
}
