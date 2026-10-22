///|
fn conditional_predicate_kind(kind : String) -> Bool {
  ["containsBlanks", "notContainsBlanks", "containsErrors", "notContainsErrors"].contains(
    kind,
  )
}

///|
fn conditional_predicate(
  kind : String,
  value : Value,
  work : FormulaWork,
) -> Bool? raise @failure.Failure {
  match kind {
    "containsErrors" => Some(value is Error(_))
    "notContainsErrors" => Some(!(value is Error(_)))
    "containsBlanks" | "notContainsBlanks" => {
      let text = value.display()
      work.spend(amount=text.length())
      Some(text.iter().all(ch => ch == ' ') == (kind == "containsBlanks"))
    }
    _ => None
  }
}

///|
fn conditional_predicate_formula(
  kind : String,
  anchor : Address,
) -> String? raise @failure.Failure {
  guard conditional_predicate_kind(kind) else { return None }
  let address = anchor.name()
  Some(
    match kind {
      "containsBlanks" => "LEN(TRIM(\{address}))=0"
      "notContainsBlanks" => "LEN(TRIM(\{address}))>0"
      "containsErrors" => "ISERROR(\{address})"
      _ => "NOT(ISERROR(\{address}))"
    },
  )
}
