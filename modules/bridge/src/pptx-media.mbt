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
fn pptx_resource_bytes(
  session : @pptx.Session,
  request : Json,
  media : Bool,
) -> Json raise @failure.Failure {
  let key = field_string(request, "key")
  {
    "bytes": @base64.encode(
      if media {
        session.media_bytes(key)
      } else {
        session.image_bytes(key)
      },
    ),
  }
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
