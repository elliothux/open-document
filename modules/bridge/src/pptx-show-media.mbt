///|
fn pptx_show_media(
  session : @pptx.Session,
  request : Json,
) -> Json raise @failure.Failure {
  guard request is { "change": change, .. } else {
    @failure.reject("invalid-operation", "Missing media change")
  }
  let keys = if field_string(change, "action") == "error" {
    ["object", "token", "action", "message"]
  } else {
    ["object", "token", "action"]
  }
  guard change is Object(fields) &&
    fields.length() == keys.length() &&
    fields.keys().all(key => keys.contains(key)) else {
    @failure.reject("invalid-operation", "Invalid media change fields")
  }
  let layout = match request {
    { "layoutId": Number(_, ..), .. } => Some(field_int(request, "layoutId"))
    { "layoutId": _, .. } =>
      @failure.reject("invalid-operation", "Invalid media frame")
    _ => None
  }
  let message = match change {
    { "message": String(message), .. } => message
    { "message": _, .. } =>
      @failure.reject("invalid-operation", "Invalid media error")
    _ => ""
  }
  session.media_show(
    field_int(request, "revision"),
    layout,
    xlsx_number(request, "time"),
    {
      object: field_string(change, "object"),
      token: field_int(change, "token"),
      action: field_string(change, "action"),
      message,
    },
  )
}
