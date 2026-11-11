///|
priv struct CommentAuthorRequest {
  text : String
  author : String
  initials : String
  date : String
} derive(@json.FromJson)

///|
priv struct CommentIdentityRequest {
  id : String
} derive(@json.FromJson)

///|
fn docx_comment_edit(
  change : Json,
) -> @model.CommentEdit raise @failure.Failure {
  guard change is Object(fields) else {
    @failure.reject("invalid-operation", "Invalid comment command")
  }
  match (change, fields.length()) {
    (
      {
        "action": String("add" | "addWord" as action),
        "selection": selection,
        ..
      },
      6,
    ) => {
      let input : CommentAuthorRequest = @common.request(change)
      let selection : SelectionRequest = @common.request(selection)
      if action == "add" {
        @model.AddComment(
          input.text,
          input.author,
          input.initials,
          input.date,
          selection.selection(),
        )
      } else {
        @model.AddWordComment(
          input.text,
          input.author,
          input.initials,
          input.date,
          selection.selection(),
        )
      }
    }
    ({ "action": String("reply"), "id": String(id), .. }, 6) => {
      let input : CommentAuthorRequest = @common.request(change)
      @model.ReplyComment(
        id,
        input.text,
        input.author,
        input.initials,
        input.date,
      )
    }
    (
      {
        "action": String("resolve"),
        "id": String(id),
        "done": True
        | False as done,
        ..
      },
      3,
    ) => @model.SetCommentResolved(id, done is True)
    (
      { "action": String("update"), "id": String(id), "text": String(text), .. },
      3,
    ) => @model.UpdateComment(id, text)
    ({ "action": String("goTo" | "remove" as action), .. }, 2) => {
      let input : CommentIdentityRequest = @common.request(change)
      if action == "goTo" {
        @model.GoToComment(input.id)
      } else {
        @model.RemoveComment(input.id)
      }
    }
    _ => @failure.reject("invalid-operation", "Invalid comment fields")
  }
}
