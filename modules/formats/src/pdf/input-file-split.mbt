///|
/// Create independent files at one source revision. All groups are validated
/// before exporting, and outputs share the existing operation and byte budgets.
pub fn PdfSession::split_files(
  self : PdfSession,
  revision : Int32,
  groups : Array[Array[String]],
) -> Array[(String, Bytes)] raise @failure.Failure {
  self.check(revision)
  guard !groups.is_empty() && groups.length() <= self.budget.pages else {
    @failure.reject("invalid-page", "Choose bounded PDF page groups")
  }
  let seen : Map[String, Bool] = Map([])
  for group in groups {
    guard !group.is_empty() else {
      @failure.reject(
        "invalid-page", "A split file must contain at least one page",
      )
    }
    for id in group {
      ignore(self.page(id))
      guard !seen.contains(id) else {
        @failure.reject(
          "invalid-page", "Split groups must contain distinct source pages",
        )
      }
      seen[id] = true
    }
  }
  pdf_bound(self.budget, () => {
    let result : Array[(String, Bytes)] = []
    let mut remaining = self.budget.outputBytes
    for index, group in groups {
      let bytes = self.extract_pages(revision, group)
      guard bytes.length() <= remaining else {
        @failure.reject(
          "limit-exceeded", "Combined PDF split output exceeds budget",
        )
      }
      remaining -= bytes.length()
      let number = (index + 1).to_string()
      let prefix = if number.length() < 3 {
        "000"[:3 - number.length()].to_owned()
      } else {
        ""
      }
      result.push(("part-" + prefix + number + ".pdf", bytes))
    }
    result
  })
}
