///|
fn table_header_names(
  labels : Array[String],
  retained : Array[String],
  initial_units : Int,
) -> Array[String] raise @failure.Failure {
  let reserved : Map[String, Bool] = Map([])
  let used : Map[String, Bool] = Map([])
  for label in retained {
    used[label.to_upper()] = true
  }
  for label in labels {
    if !label.is_empty() {
      reserved[label.to_upper()] = true
    }
  }
  let result : Array[String] = []
  let mut units = initial_units
  for original in labels {
    let label = if !original.is_empty() && !used.contains(original.to_upper()) {
      original
    } else {
      for suffix in (if original.is_empty() { 1 } else { 2 })..<=8193 {
        let candidate = (if original.is_empty() { "Column" } else { original }) +
          suffix.to_string()
        if !used.contains(candidate.to_upper()) &&
          !reserved.contains(candidate.to_upper()) {
          break candidate
        }
      } nobreak {
        @failure.reject("limit-exceeded", "Table header identities exhausted")
      }
    }
    units += label.length()
    guard label.length() <= 255 && units <= 65536 && @xml.valid_text(label) else {
      @failure.reject("limit-exceeded", "Table column metadata exceeds budget")
    }
    used[label.to_upper()] = true
    result.push(label)
  }
  result
}
