///|
fn xlsx_comments_operation(
  session : @xlsx.Session,
  operation : String,
  request : Json,
) -> Json raise @failure.Failure {
  let revision = field_int(request, "revision")
  let sheet = field_string(request, "sheet")
  if operation == "threadsXlsx" {
    return session.threads(revision, sheet, field_string(request, "cell"))
  }
  guard request is { "change": change, .. } else {
    @failure.reject("invalid-operation", "Thread change is required")
  }
  let action = field_string(change, "action")
  let edit : @xlsx.ThreadEdit = match action {
    "create" =>
      CreateThread(
        field_string(change, "cell"),
        field_string(change, "text"),
        field_string(change, "author"),
        field_string(change, "date"),
      )
    "reply" =>
      ReplyThread(
        field_string(change, "id"),
        field_string(change, "text"),
        field_string(change, "author"),
        field_string(change, "date"),
      )
    "update" =>
      UpdateThread(field_string(change, "id"), field_string(change, "text"))
    "resolve" =>
      ResolveThread(
        field_string(change, "id"),
        xlsx_boolean(change, "resolved"),
      )
    "delete" => DeleteThread(field_string(change, "id"))
    _ => @failure.reject("invalid-operation", "Unknown thread edit")
  }
  session.edit_thread(revision, sheet, edit)
}
