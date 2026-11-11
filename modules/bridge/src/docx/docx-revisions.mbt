///|
priv struct ResolveRevisionRequest {
  action : String
  ids : Array[String]
} derive(@json.FromJson)

///|
priv struct ResolveRevisionEnvelope {
  revision : @common.RequestInt
  change : ResolveRevisionRequest
} derive(@json.FromJson)

///|
fn Context::resolve_revision_command(
  self : Context,
  session : @model.Session,
  request : Json,
) -> Json raise @failure.Failure {
  guard request is { "change": Object(fields), .. } &&
    fields.length() == 2 &&
    fields.get("ids") is Some(Array(ids)) &&
    !ids.is_empty() &&
    ids.length() <= @model.RevisionEntries else {
    @failure.reject("invalid-operation", "Invalid revision command")
  }
  let envelope : ResolveRevisionEnvelope = @common.request(request)
  let command = envelope.change
  guard ["accept", "reject"].contains(command.action) else {
    @failure.reject("invalid-operation", "Invalid revision command")
  }
  let result = session.resolve_revisions(
    envelope.revision.value,
    command.ids,
    command.action == "accept",
  )
  self.layout = None
  result
}
