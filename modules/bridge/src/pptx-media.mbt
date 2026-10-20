///|
fn pptx_insert_media(change : Json) -> @pptx.ObjectEdit raise @failure.Failure {
  @pptx.InsertMedia(
    field_string(change, "kind"),
    field_string(change, "contentType"),
    input_bytes(change, 16777216),
    input_bytes({ "bytes": field_string(change, "poster") }, 4194304),
    xlsx_number(change, "x"),
    xlsx_number(change, "y"),
    xlsx_number(change, "width"),
    xlsx_number(change, "height"),
  )
}

///|
fn pptx_media_bytes(
  session : @pptx.Session,
  request : Json,
) -> Json raise @failure.Failure {
  { "bytes": @base64.encode(session.media_bytes(field_string(request, "key"))) }
}

///|
fn pptx_media_playback(
  change : Json,
) -> @pptx.ObjectEdit raise @failure.Failure {
  guard change is { "value": Object(value), .. } &&
    value.length() == 3 &&
    value.keys().all(key => ["loop", "volume", "mute"].contains(key)) else {
    @failure.reject("invalid-operation", "Media playback settings are required")
  }
  let value = Json::object(value)
  @pptx.MediaPlayback({
    cycling: xlsx_boolean(value, "loop"),
    volume: field_int(value, "volume"),
    mute: xlsx_boolean(value, "mute"),
  })
}
