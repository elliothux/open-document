///|
#derive(@json.FromJson)
priv struct ShowLayoutRequest {
  revision : @common.RequestInt
  time : @common.RequestNumber
  profile : @common.RequestProfile
}

///|
#derive(@json.FromJson)
priv struct ShowControlRequest {
  revision : @common.RequestInt
  action : String
  slide : String
  time : @common.RequestNumber
  custom : String?
  layoutId : @common.RequestInt?
  x : @common.RequestNumber?
  y : @common.RequestNumber?
}

///|
#derive(@json.FromJson)
priv struct ShowInkRequest {
  revision : @common.RequestInt
  layoutId : @common.RequestInt
  time : @common.RequestNumber
  change : Json
}

///|
#derive(@json.FromJson)
priv struct ShowMediaRequest {
  revision : @common.RequestInt
  layoutId : @common.RequestInt?
  time : @common.RequestNumber
  change : Json
}

///|
let show_handlers : Map[
  String,
  (Context, @model.Session, Json) -> Json raise @failure.Failure,
] = {
  "layoutShowPptx": (context, session, input) => {
    let command : ShowLayoutRequest = @common.request(input)
    session.show_layout(
      command.revision.value,
      command.time.value,
      context.probe,
      command.profile.value,
      context.images,
    )
  },
  "controlShowPptx": (_context, session, input) => {
    let command : ShowControlRequest = @common.request(input)
    let point = match (command.x, command.y) {
      (Some(x), Some(y)) => Some((x.value, y.value))
      (None, None) => None
      _ =>
        @failure.reject(
          "invalid-operation", "Both show point coordinates are required",
        )
    }
    session.control_show(
      command.revision.value,
      command.action,
      command.slide,
      command.time.value,
      custom=command.custom,
      layout=command.layoutId.map(value => value.value),
      point~,
    )
  },
  "inkShowPptx": (_context, session, input) => {
    let command : ShowInkRequest = @common.request(input)
    session.ink_show(
      command.revision.value,
      command.layoutId.value,
      command.time.value,
      pptx_show_ink(command.change),
    )
  },
  "mediaShowPptx": (_context, session, input) => {
    let command : ShowMediaRequest = @common.request(input)
    session.media_show(
      command.revision.value,
      command.layoutId.map(value => value.value),
      command.time.value,
      pptx_show_media(command.change),
    )
  },
}
