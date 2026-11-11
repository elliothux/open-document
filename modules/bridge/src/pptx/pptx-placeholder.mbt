///|
#derive(@json.FromJson(fields(kind(rename="type"))))
priv struct PlaceholderKindRequest {
  kind : String
}

///|
#derive(@json.FromJson(fields(kind(rename="type"))))
priv struct PlaceholderDefinitionRequest {
  kind : String
  index : @common.RequestNumber
}

///|
#derive(@json.FromJson)
priv struct InsertShapeKindRequest {
  kind : String
}

///|
#derive(@json.FromJson)
priv struct InsertObjectFrameRequest {
  x : @common.RequestNumber
  y : @common.RequestNumber
  width : @common.RequestNumber
  height : @common.RequestNumber
  text : String
}

///|
fn pptx_placeholder(change : Json) -> @model.ObjectEdit raise @failure.Failure {
  guard change is Object(fields) &&
    fields.length() == 2 &&
    fields.get("value") is Some(value) else {
    @failure.reject("invalid-operation", "Invalid placeholder edit fields")
  }
  if value is Null {
    return @model.Placeholder(None, 0)
  }
  guard value is Object(fields) && fields.length() == 2 else {
    @failure.reject("invalid-operation", "Invalid placeholder definition")
  }
  let request : PlaceholderDefinitionRequest = @common.request(value)
  @model.Placeholder(Some(request.kind), request.index.value)
}

///|
fn pptx_insert_object(
  action : String,
  change : Json,
) -> @model.ObjectEdit raise @failure.Failure {
  let frame : InsertObjectFrameRequest = @common.request(change)
  if action == "insert" {
    let request : InsertShapeKindRequest = @common.request(change)
    return @model.Insert(
      request.kind,
      frame.x.value,
      frame.y.value,
      frame.width.value,
      frame.height.value,
      frame.text,
    )
  }
  guard action == "insertPlaceholder" &&
    change is Object(fields) &&
    fields.length() == 7 else {
    @failure.reject("invalid-operation", "Invalid placeholder insertion fields")
  }
  let request : PlaceholderKindRequest = @common.request(change)
  @model.InsertPlaceholder(
    request.kind,
    frame.x.value,
    frame.y.value,
    frame.width.value,
    frame.height.value,
    frame.text,
  )
}
