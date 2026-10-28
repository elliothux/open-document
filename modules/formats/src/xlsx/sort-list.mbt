///|
priv struct SortValue {
  value : Value
  rank : Int32?
}

///|
priv struct SortList {
  exact : Map[String, Int32]
  folded : Map[String, Int32]
}

///|
fn check_sort_list(values : Array[String]) -> Unit raise @failure.Failure {
  guard values.length() <= 4096 else {
    @failure.reject(
      "limit-exceeded", "Custom sort lists support at most 4096 labels",
    )
  }
  let seen : Map[String, Bool] = Map([])
  let mut units = (values.length() - 1).max(0)
  for value in values {
    units += value.length()
    guard !value.is_empty() &&
      !value.contains(",") &&
      !value.contains("\n") &&
      !value.contains("\r") &&
      @xml.valid_text(value) &&
      !seen.contains(value) &&
      units <= 32767 else {
      @failure.reject(
        "invalid-operation", "Custom sort labels must be distinct nonempty text without commas or line breaks and fit 32767 units",
      )
    }
    seen[value] = true
  }
}

///|
fn SortList::new(
  values : Array[String],
  work : FormulaWork,
) -> SortList raise @failure.Failure {
  check_sort_list(values)
  let exact : Map[String, Int32] = Map([])
  let folded : Map[String, Int32] = Map([])
  for index, value in values {
    exact[value] = index
    let normalized = formula_case(value, true, work)
    guard normalized is Text(text) else {
      @failure.reject(
        "limit-exceeded", "Custom sort labels exceed case mapping budget",
      )
    }
    if !folded.contains(text) {
      folded[text] = index
    }
  }
  { exact, folded, }
}

///|
fn SortList::value(
  self : SortList,
  raw : Value,
  sensitive : Bool,
  work : FormulaWork,
) -> SortValue raise @failure.Failure {
  let value = sort_value(raw, sensitive, work)
  let rank = if value is Text(_) && !self.exact.is_empty() {
    let text = raw.display()
    if self.exact.get(text) is Some(rank) {
      Some(rank)
    } else {
      guard formula_case(text, true, work) is Text(folded) else {
        @failure.reject(
          "limit-exceeded", "Custom sort keys exceed case mapping budget",
        )
      }
      self.folded.get(folded)
    }
  } else {
    None
  }
  { value, rank, }
}

///|
fn sort_list_compare(a : SortValue, b : SortValue, descending : Bool) -> Int32 {
  if (a.value, b.value) is (Text(_), Text(_)) {
    let result = match (a.rank, b.rank) {
      (Some(a), Some(b)) => a.compare(b)
      (Some(_), None) => -1
      (None, Some(_)) => 1
      (None, None) => return sort_compare(a.value, b.value, descending)
    }
    if descending {
      -result
    } else {
      result
    }
  } else {
    sort_compare(a.value, b.value, descending)
  }
}

///|
fn sort_list_attribute(values : Array[String]) -> String raise @failure.Failure {
  if values.is_empty() {
    ""
  } else {
    let text = encode_text(values.join(","))
      .replace_all(old="\t", new="_x0009_")
      .replace_all(old="\"", new="&quot;")
    " customList=\"" + text + "\""
  }
}
