///|
priv struct ShowMediaChangeRequest {
  object : String
  token : @common.RequestInt
  action : String
} derive(@json.FromJson)

///|
priv struct ShowMediaErrorRequest {
  message : String
} derive(@json.FromJson)

///|
fn pptx_show_media(
  change : Json,
) -> @model.ShowMediaChange raise @failure.Failure {
  let request : ShowMediaChangeRequest = @common.request(change)
  let error = request.action == "error"
  guard change is Object(fields) &&
    fields.length() == (if error { 4 } else { 3 }) else {
    @failure.reject("invalid-operation", "Invalid media change fields")
  }
  let message = if error {
    let error_request : ShowMediaErrorRequest = @common.request(change)
    error_request.message
  } else {
    ""
  }
  {
    object: request.object,
    token: request.token.value,
    action: request.action,
    message,
  }
}
