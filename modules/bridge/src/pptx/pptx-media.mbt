///|
#derive(@json.FromJson)
priv struct MediaKindRequest {
  bytes : String
  kind : String
  contentType : String
}

///|
#derive(@json.FromJson)
priv struct MediaPosterRequest {
  poster : String
}

///|
#derive(@json.FromJson(fields(cycling(rename="loop"))))
priv struct MediaPlaybackRequest {
  cycling : Bool
  volume : @common.RequestInt
  mute : Bool
}

///|
fn pptx_insert_media(
  action : String,
  change : Json,
) -> @model.ObjectEdit raise @failure.Failure {
  let request : MediaKindRequest = @common.request(change)
  let bytes = @common.byte_input(request.bytes, @model.MediaInputBytes)
  let poster_request : MediaPosterRequest = @common.request(change)
  let poster = @common.byte_input(poster_request.poster, @model.ImageInputBytes)
  if action == "fillMedia" {
    return @model.FillMedia(request.kind, request.contentType, bytes, poster)
  }
  let frame : ObjectFrameRequest = @common.request(change)
  @model.InsertMedia(
    request.kind,
    request.contentType,
    bytes,
    poster,
    frame.x.value,
    frame.y.value,
    frame.width.value,
    frame.height.value,
  )
}

///|
fn pptx_media_playback(
  change : Json,
) -> @model.ObjectEdit raise @failure.Failure {
  guard change is { "value": Object(fields) as value, .. } &&
    fields.length() == 3 else {
    @failure.reject("invalid-operation", "Media playback settings are required")
  }
  let request : MediaPlaybackRequest = @common.request(value)
  @model.MediaPlayback({
    cycling: request.cycling,
    volume: request.volume.value,
    mute: request.mute,
  })
}
