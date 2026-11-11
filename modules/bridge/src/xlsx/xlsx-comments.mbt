///|
#derive(@json.FromJson)
priv struct ThreadsRequest {
  revision : @common.RequestInt
  sheet : String
  cell : String
}

///|
#derive(@json.FromJson)
priv struct ThreadEditRequest {
  revision : @common.RequestInt
  sheet : String
  change : Json
}

///|
#derive(@json.FromJson)
priv struct ThreadActionRequest {
  action : String
}

///|
#derive(@json.FromJson)
priv struct ThreadCreateRequest {
  cell : String
  text : String
  author : String
  date : String
}

///|
#derive(@json.FromJson)
priv struct ThreadReplyRequest {
  id : String
  text : String
  author : String
  date : String
}

///|
#derive(@json.FromJson)
priv struct ThreadUpdateRequest {
  id : String
  text : String
}

///|
#derive(@json.FromJson)
priv struct ThreadResolveRequest {
  id : String
  resolved : Bool
}

///|
#derive(@json.FromJson)
priv struct ThreadDeleteRequest {
  id : String
}

///|
fn xlsx_thread_edit(input : Json) -> @model.ThreadEdit raise @failure.Failure {
  let command : ThreadActionRequest = @common.request(input)
  match command.action {
    "create" => {
      let command : ThreadCreateRequest = @common.request(input)
      @model.CreateThread(
        command.cell,
        command.text,
        command.author,
        command.date,
      )
    }
    "reply" => {
      let command : ThreadReplyRequest = @common.request(input)
      @model.ReplyThread(command.id, command.text, command.author, command.date)
    }
    "update" => {
      let command : ThreadUpdateRequest = @common.request(input)
      @model.UpdateThread(command.id, command.text)
    }
    "resolve" => {
      let command : ThreadResolveRequest = @common.request(input)
      @model.ResolveThread(command.id, command.resolved)
    }
    "delete" => {
      let command : ThreadDeleteRequest = @common.request(input)
      @model.DeleteThread(command.id)
    }
    _ => @failure.reject("invalid-operation", "Unknown thread edit")
  }
}

///|
let thread_handlers : Map[
  String,
  (Context, @model.Session, Json) -> Json raise @failure.Failure,
] = {
  "threadsXlsx": (_context, session, input) => {
    let command : ThreadsRequest = @common.request(input)
    session.threads(command.revision.value, command.sheet, command.cell)
  },
  "editThreadXlsx": (_context, session, input) => {
    let command : ThreadEditRequest = @common.request(input)
    session.edit_thread(
      command.revision.value,
      command.sheet,
      xlsx_thread_edit(command.change),
    )
  },
}
