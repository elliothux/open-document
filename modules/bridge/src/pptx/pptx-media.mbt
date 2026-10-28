///|
fn pptx_insert_media(change : Json) -> @model.ObjectEdit raise @failure.Failure {
  if field_string(change, "action") == "fillMedia" {
    return @model.FillMedia(
      field_string(change, "kind"),
      field_string(change, "contentType"),
      input_bytes(change, 16777216),
      input_bytes({ "bytes": field_string(change, "poster") }, 4194304),
    )
  }
  @model.InsertMedia(
    field_string(change, "kind"),
    field_string(change, "contentType"),
    input_bytes(change, 16777216),
    input_bytes({ "bytes": field_string(change, "poster") }, 4194304),
    field_number(change, "x"),
    field_number(change, "y"),
    field_number(change, "width"),
    field_number(change, "height"),
  )
}

///|
fn pptx_resource_bytes(
  session : @model.Session,
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
) -> @model.ObjectEdit raise @failure.Failure {
  guard change is { "value": Object(value), .. } &&
    value.length() == 3 &&
    value.keys().all(key => ["loop", "volume", "mute"].contains(key)) else {
    @failure.reject("invalid-operation", "Media playback settings are required")
  }
  let value = Json::object(value)
  @model.MediaPlayback({
    cycling: field_boolean(value, "loop"),
    volume: field_int(value, "volume"),
    mute: field_boolean(value, "mute"),
  })
}
