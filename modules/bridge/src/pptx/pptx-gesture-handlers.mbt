///|
priv struct GuideRequest {
  revision : @common.RequestInt
  x : @common.RequestNumber
  y : @common.RequestNumber
  tolerance : @common.RequestNumber
} derive(@json.FromJson)

///|
priv struct BeginRequest {
  revision : @common.RequestInt
  kind : String
} derive(@json.FromJson)

///|
priv struct TransformRequest {
  revision : @common.RequestInt
  candidateId : @common.RequestInt
  x : @common.RequestNumber
  y : @common.RequestNumber
  width : @common.RequestNumber
  height : @common.RequestNumber
} derive(@json.FromJson)

///|
priv struct DragRequest {
  revision : @common.RequestInt
  candidateId : @common.RequestInt
  dx : @common.RequestNumber
  dy : @common.RequestNumber
  handle : @common.RequestInt
  shift : Bool?
  center : Bool?
  tolerance : @common.RequestNumber?
} derive(@json.FromJson)

///|
priv struct FinishRequest {
  revision : @common.RequestInt
  candidateId : @common.RequestInt
  profile : @common.RequestProfile
} derive(@json.FromJson)

///|
priv struct CancelRequest {
  revision : @common.RequestInt
  candidateId : @common.RequestInt
} derive(@json.FromJson)

///|
let gesture_handlers : Map[
  String,
  (Context, @model.Session, Json) -> Json raise @failure.Failure,
] = {
  "beginGuidePptx": (_context, session, input) => {
    let command : GuideRequest = @common.request(input)
    session.begin_guide(
      command.revision.value,
      command.x.value,
      command.y.value,
      command.tolerance.value,
    )
  },
  "beginPptx": (_context, session, input) => {
    let command : BeginRequest = @common.request(input)
    session.begin(command.revision.value, command.kind)
  },
  "transformPptx": (_context, session, input) => {
    let command : TransformRequest = @common.request(input)
    session.transform(
      command.revision.value,
      command.candidateId.value,
      command.x.value,
      command.y.value,
      command.width.value,
      command.height.value,
    )
  },
  "dragPptx": (_context, session, input) => {
    let command : DragRequest = @common.request(input)
    session.drag(
      command.revision.value,
      command.candidateId.value,
      command.dx.value,
      command.dy.value,
      command.handle.value,
      shift=command.shift.unwrap_or(false),
      center=command.center.unwrap_or(false),
      tolerance=command.tolerance.map(value => value.value).unwrap_or(0),
    )
  },
  "finishPptx": (context, session, input) => {
    let command : FinishRequest = @common.request(input)
    session.finish(
      command.revision.value,
      command.candidateId.value,
      context.probe,
      command.profile.value,
    )
  },
  "cancelPptx": (_context, session, input) => {
    let command : CancelRequest = @common.request(input)
    session.cancel(command.revision.value, command.candidateId.value)
  },
}
