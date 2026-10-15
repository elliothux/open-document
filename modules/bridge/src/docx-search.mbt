///|
fn find_options(request : Json) -> @docx.FindOptions raise @failure.Failure {
  guard request is { "options": Object(fields), .. } &&
    fields.keys().all(key => key == "matchCase" || key == "wholeWord") else {
    @failure.reject("invalid-operation", "Invalid literal search options")
  }
  let boolean = fn(key : String) raise @failure.Failure {
    match fields.get(key) {
      None | Some(False) => false
      Some(True) => true
      _ => @failure.reject("invalid-operation", "Invalid search option: " + key)
    }
  }
  @docx.FindOptions::new(
    matchCase=boolean("matchCase"),
    wholeWord=boolean("wholeWord"),
  )
}

///|
fn replacement_matches(
  request : Json,
) -> Array[@docx.Selection] raise @failure.Failure {
  guard request is { "matches": Array(matches), .. } && matches.length() <= 1000 else {
    @failure.reject(
      "invalid-operation", "Expected at most 1000 replacement ranges",
    )
  }
  matches.map(selection => field_selection({ "selection": selection }))
}
