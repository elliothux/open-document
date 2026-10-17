///|
fn docx_comment_edit(
  request : Json,
) -> @docx.CommentEdit raise @failure.Failure {
  guard request is { "change": Object(fields) as change, .. } else {
    @failure.reject("invalid-operation", "Invalid comment command")
  }
  let action = field_string(change, "action")
  let allowed = match action {
    "add" | "addWord" =>
      ["action", "text", "author", "initials", "date", "selection"]
    "reply" => ["action", "id", "text", "author", "initials", "date"]
    "resolve" => ["action", "id", "done"]
    "update" => ["action", "id", "text"]
    "remove" | "goTo" => ["action", "id"]
    _ => @failure.reject("invalid-operation", "Unknown comment command")
  }
  guard fields.length() == allowed.length() &&
    fields.keys().all(k => allowed.contains(k)) else {
    @failure.reject("invalid-operation", "Invalid comment fields")
  }
  match action {
    "reply" =>
      @docx.ReplyComment(
        field_string(change, "id"),
        field_string(change, "text"),
        field_string(change, "author"),
        field_string(change, "initials"),
        field_string(change, "date"),
      )
    "resolve" => {
      guard fields.get("done") is Some(True | False as done) else {
        @failure.reject("invalid-operation", "Invalid comment resolved state")
      }
      @docx.SetCommentResolved(field_string(change, "id"), done is True)
    }
    "add" =>
      @docx.AddComment(
        field_string(change, "text"),
        field_string(change, "author"),
        field_string(change, "initials"),
        field_string(change, "date"),
        field_selection(change),
      )
    "addWord" =>
      @docx.AddWordComment(
        field_string(change, "text"),
        field_string(change, "author"),
        field_string(change, "initials"),
        field_string(change, "date"),
        field_selection(change),
      )
    "update" =>
      @docx.UpdateComment(
        field_string(change, "id"),
        field_string(change, "text"),
      )
    "goTo" => @docx.GoToComment(field_string(change, "id"))
    _ => @docx.RemoveComment(field_string(change, "id"))
  }
}
