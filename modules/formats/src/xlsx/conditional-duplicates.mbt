///|
fn ConditionalRules::duplicate_match(
  self : ConditionalRules,
  rule : ConditionalRule,
  address : Address,
  sheets : Array[Sheet],
  index : Int,
  values : Map[(Int, String), Value],
  work : FormulaWork,
) -> Bool raise @failure.Failure {
  let key = calculated_cell(sheets, values, index, address).display()
  work.spend(amount=key.length())
  guard !key.is_empty() else { return false }
  let duplicates = self.duplicates
    .get(rule.priority)
    .unwrap_or_else(() => {
      let duplicates : Map[String, Bool] = Map([])
      for cell in sheets[index].cells.values() {
        work.spend()
        if !rule.ranges.any(range => {
            work.spend()
            range.contains(cell.address)
          }) {
          continue
        }
        let value = calculated_cell(sheets, values, index, cell.address).display()
        work.spend(amount=value.length())
        if !value.is_empty() {
          duplicates[value] = duplicates.contains(value)
        }
      }
      self.duplicates[rule.priority] = duplicates
      duplicates
    })
  duplicates
  .get(key)
  .map(duplicate => duplicate == (rule.kind == "duplicateValues"))
  .unwrap_or(false)
}
