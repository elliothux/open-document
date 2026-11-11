///|
priv struct CommentAuthorRequest {
  name : String
  initials : String
} derive(@json.FromJson)

///|
priv struct AddCommentRequest {
  text : String
  author : CommentAuthorRequest
  date : String
  parent : @common.RequiredNullable[String]
} derive(@json.FromJson)

///|
priv struct UpdateCommentRequest {
  id : String
  text : String
} derive(@json.FromJson)

///|
priv struct CommentStatusRequest {
  id : String
  status : String
} derive(@json.FromJson)

///|
fn pptx_comment_change(
  action : String,
  change : Json,
) -> @model.SlideEdit raise @failure.Failure {
  match action {
    "commentAdd" => {
      let request : AddCommentRequest = @common.request(change)
      @model.AddComment(
        request.text,
        request.author.name,
        request.author.initials,
        request.date,
        request.parent.value,
      )
    }
    "commentUpdate" => {
      let request : UpdateCommentRequest = @common.request(change)
      @model.UpdateComment(request.id, request.text)
    }
    "commentRemove" => {
      let request : IdRequest = @common.request(change)
      @model.RemoveComment(request.id)
    }
    "commentStatus" => {
      let request : CommentStatusRequest = @common.request(change)
      @model.CommentStatus(request.id, request.status)
    }
    _ => @failure.reject("invalid-operation", "Expected a comment edit")
  }
}
