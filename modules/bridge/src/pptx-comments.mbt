///|
fn pptx_comment_change(change : Json) -> @pptx.SlideEdit raise @failure.Failure {
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
      @pptx.AddComment(
        field_string(change, "text"),
        field_string(author, "name"),
        field_string(author, "initials"),
        field_string(change, "date"),
        parent,
      )
    }
    "commentUpdate" =>
      @pptx.UpdateComment(
        field_string(change, "id"),
        field_string(change, "text"),
      )
    "commentRemove" => @pptx.RemoveComment(field_string(change, "id"))
    "commentStatus" =>
      @pptx.CommentStatus(
        field_string(change, "id"),
        field_string(change, "status"),
      )
    _ => @failure.reject("invalid-operation", "Expected a comment edit")
  }
}
