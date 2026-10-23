///|
fn Session::icon_sort_key(
  self : Session,
  index : Int,
  address : Address,
  key : SortKey,
  rules : ConditionalRules,
  work : FormulaWork,
) -> SortValue raise @failure.Failure {
  let matches = self.cell_icon_matches(
    index,
    address,
    key.icon_set,
    if key.icon_set.is_empty() {
      None
    } else {
      Some(key.icon_id)
    },
    rules,
    work,
  )
  { value: Number(if matches { 0 } else { 1 }), rank: None, }
}
