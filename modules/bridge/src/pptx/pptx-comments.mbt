///|
fn pptx_comment_change(
  change : Json,
) -> @model.SlideEdit raise @failure.Failure {
  match field_string(change, "action") {
    "commentAdd" => {
      guard change is { "author": author, "parent": parent, .. } else {
        @failure.reject(
          "invalid-operation", "Comment author and reply parent are required",
        )
      }
      let parent = match parent {
        Null => None
        String(id) => Some(id)
        _ =>
          @failure.reject("invalid-operation", "Invalid comment reply parent")
      }
      @model.AddComment(
        field_string(change, "text"),
        field_string(author, "name"),
        field_string(author, "initials"),
        field_string(change, "date"),
        parent,
      )
    }
    "commentUpdate" =>
      @model.UpdateComment(
        field_string(change, "id"),
        field_string(change, "text"),
      )
    "commentRemove" => @model.RemoveComment(field_string(change, "id"))
    "commentStatus" =>
      @model.CommentStatus(
        field_string(change, "id"),
        field_string(change, "status"),
      )
    _ => @failure.reject("invalid-operation", "Expected a comment edit")
  }
}
