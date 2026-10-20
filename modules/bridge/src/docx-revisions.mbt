///|
fn Foundation::docx_revisions(
  self : Foundation,
  session : @docx.Session,
  request : Json,
  operation : String,
) -> Json raise @failure.Failure {
  let revision = field_int(request, "revision")
  if operation == "docxRevisions" {
    return session.revisions(revision)
  }
  if operation == "docxRevisionGeometry" {
    let layout = self.current_layout(request)
    return {
      "layoutId": self.layout_id,
      "revision": layout.revision,
      "rects": session.revision_rects(
        revision,
        layout,
        field_string(request, "revisionId"),
      ),
    }
  }
  guard request is { "change": Object(fields), .. } &&
    fields.length() == 2 &&
    fields.contains("action") &&
    fields.contains("ids") else {
    @failure.reject(
      "invalid-operation", "Explicit revision action and identities are required",
    )
  }
  let change = Json::object(fields)
  let action = field_string(change, "action")
  guard ["accept", "reject"].contains(action) &&
    fields.get("ids") is Some(Array(ids)) &&
    !ids.is_empty() &&
    ids.length() <= 4096 else {
    @failure.reject("invalid-operation", "Invalid revision command")
  }
  let ids = ids.map(value => {
    match value {
      String(id) => id
      _ =>
        @failure.reject("invalid-operation", "Revision identity must be text")
    }
  })
  let result = session.resolve_revisions(revision, ids, action == "accept")
  self.layout = None
  result
}
