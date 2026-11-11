///|
priv struct ConditionalMemo[T] {
  used : Map[Int32, T]
  shared : (Map[Int32, (T, Int32)], Ref[Int32])?
}

///|
fn[T] ConditionalMemo::new(remaining? : Ref[Int32]) -> ConditionalMemo[T] {
  { used: Map([]), shared: remaining.map(budget => (Map([]), budget)), }
}

///|
fn[T] ConditionalMemo::value(
  self : ConditionalMemo[T],
  priority : Int32,
  work : FormulaWork,
  compute : () -> T raise @failure.Failure,
) -> T raise @failure.Failure {
  if self.used.get(priority) is Some(value) {
    return value
  }
  let before = work.remaining
  let value = if self.shared is Some((entries, _)) &&
    entries.get(priority) is Some((value, cost)) &&
    cost <= before {
    work.spend(amount=cost)
    value
  } else {
    let value = compute()
    let cost = before - work.remaining
    // The cost covers the retained values, including duplicate text lengths.
    if self.shared is Some((entries, remaining)) &&
      !entries.contains(priority) &&
      cost < remaining.val {
      entries[priority] = (value, cost)
      remaining.val -= cost + 1
    }
    value
  }
  self.used[priority] = value
  value
}

///|
priv struct ConditionalRead {
  sheet : Int32
  date : (Int32, Int32, Int32)?
  calculation : Calculation?
  rules : ConditionalRules
  cost : Int32
}

///|
fn Session::read_conditional_rules(
  self : Session,
  index : Int32,
  work : FormulaWork,
) -> ConditionalRules raise @failure.Failure {
  let cache = self.read_cache()
  let before = work.remaining
  let rules = if cache.conditional is Some(entry) &&
    entry.sheet == index &&
    entry.date == self.calendar_date &&
    physical_equal(entry.calculation, self.calculation) &&
    entry.cost <= before {
    work.spend(amount=entry.cost)
    entry.rules
  } else {
    let rules = self.conditional_rules(
      self.sheets[index],
      index,
      self.sheets,
      work,
    )
    let remaining = Ref(1048576)
    let rules = {
      ..rules,
      scales: ConditionalMemo::new(remaining~),
      duplicates: ConditionalMemo::new(remaining~),
    }
    cache.conditional = Some({
      sheet: index,
      date: self.calendar_date,
      calculation: self.calculation,
      rules,
      cost: before - work.remaining,
    })
    rules
  }
  // Charge each statistic once per operation, even if it was computed earlier.
  {
    ..rules,
    scales: { ..rules.scales, used: Map([]), },
    duplicates: { ..rules.duplicates, used: Map([]), },
  }
}
