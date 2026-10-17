///|
fn Session::prepare_filter(
  self : Session,
  sheet : Int,
  range : Range,
  column : FilterColumn,
  work : FormulaWork,
) -> PreparedFilter raise @failure.Failure {
  match column.rule {
    Rank(value, top~, percent~) =>
      Ranking(
        self.rank_threshold(
          sheet,
          range,
          column.column,
          value,
          top,
          percent,
          work,
        ),
        top~,
      )
    _ => column.rule.prepare(work)
  }
}

///|
fn Session::rank_threshold(
  self : Session,
  sheet : Int,
  range : Range,
  column : Int,
  value : Int,
  top : Bool,
  percent : Bool,
  work : FormulaWork,
) -> Double? raise @failure.Failure {
  let numbers : Array[Double] = []
  for row in (range.top + 1)..<=range.bottom {
    work.spend(amount=1)
    if self.filter_raw(sheet, row, column) is Number(number) {
      numbers.push(number)
    }
  }
  guard !numbers.is_empty() else { return None }
  work.spend(amount=numbers.length() * 13)
  numbers.sort_by((a, b) => if a < b { -1 } else if a > b { 1 } else { 0 })
  // Rank counts include duplicates; ties at the inclusive threshold remain visible.
  let count = (if percent { numbers.length() * value / 100 } else { value })
    .max(1)
    .min(numbers.length())
  Some(numbers[if top { numbers.length() - count } else { count - 1 }])
}
