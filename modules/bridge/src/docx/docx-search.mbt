///|
priv struct FindRequest {
  revision : @common.RequestInt
  text : String
  options : Map[String, Bool]
} derive(@json.FromJson)

///|
priv struct ReplaceMatchesRequest {
  revision : @common.RequestInt
  text : String
  matches : Array[SelectionRequest]
} derive(@json.FromJson)

///|
let search_handlers : Map[
  String,
  (Context, @model.Session, Json) -> Json raise @failure.Failure,
] = {
  "findDocx": (_context, session, input) => {
    guard input is { "options": Object(fields), .. } &&
      fields.length() <= 2 &&
      fields.keys().all(key => key == "matchCase" || key == "wholeWord") else {
      @failure.reject("invalid-operation", "Invalid literal search options")
    }
    let command : FindRequest = @common.request(input)
    session.find(
      command.revision.value,
      command.text,
      @model.FindOptions::new(
        matchCase=command.options.get("matchCase").unwrap_or(false),
        wholeWord=command.options.get("wholeWord").unwrap_or(false),
      ),
    )
  },
  "replaceDocxMatches": (context, session, input) => {
    guard input is { "matches": Array(matches), .. } &&
      matches.length() <= @model.SearchMatchLimit else {
      @failure.reject(
        "invalid-operation",
        "Expected at most \{@model.SearchMatchLimit} replacement ranges",
      )
    }
    let command : ReplaceMatchesRequest = @common.request(input)
    let revision = command.revision.value
    context.clear_edit_layout(
      session.replace_matches(
        revision,
        command.matches.map(selection => selection.selection()),
        command.text,
      ),
      previous=revision,
    )
  },
}
