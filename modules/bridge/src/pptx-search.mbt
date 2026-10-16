///|
fn Foundation::pptx_search(
  self : Foundation,
  session : @pptx.Session,
  operation : String,
  request : Json,
) -> Json raise @failure.Failure {
  guard request is { "options": Object(fields), .. } &&
    fields.keys().all(key => ["matchCase", "wholeWord", "all"].contains(key)) else {
    @failure.reject("invalid-operation", "Invalid presentation search options")
  }
  let boolean = fn(key : String, default_value : Bool) raise @failure.Failure {
    match fields.get(key) {
      None => default_value
      Some(True) => true
      Some(False) => false
      _ =>
        @failure.reject(
          "invalid-operation", "Invalid presentation search option",
        )
    }
  }
  let options = @pptx.FindOptions::new(
    matchCase=boolean("matchCase", false),
    wholeWord=boolean("wholeWord", false),
    all=boolean("all", true),
  )
  let revision = field_int(request, "revision")
  let slide = field_string(request, "slide")
  let text = field_string(request, "text")
  if operation == "findPptx" {
    session.find(revision, slide, text, options)
  } else {
    let index = match request {
      { "index": Null, .. } => None
      { "index": _, .. } => Some(field_int(request, "index"))
      _ => None
    }
    session.replace_matches(
      revision,
      slide,
      text,
      options,
      field_string(request, "replacement"),
      index,
      self.probe,
      xlsx_profile(request),
    )
  }
}
